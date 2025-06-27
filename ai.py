# -*- coding: utf-8 -*-

import argparse
import logging
import os
import pickle
import platform
import re
import signal
import subprocess
import sys
import time
from collections import OrderedDict
import configparser

try:
    import distro
except ImportError:
    distro = None

try:
    import openai
except ImportError:
    openai = None

log = logging.getLogger(__name__)
log.setLevel(logging.ERROR)
# logging goes into stderr
logging.basicConfig(
    level=logging.ERROR, format="[%(name)s]\t%(asctime)s - %(levelname)s \t %(message)s"
)

VERSION = "0.8.0"
PLATFORM = platform.system()
if PLATFORM == "Linux":
    CACHE_FOLDER = "/opt/TerminalAI"
elif PLATFORM == "Darwin":
    PLATFORM = "MacOSX"
    CACHE_FOLDER = "/opt/TerminalAI"
elif PLATFORM == "Windows":
    CACHE_FOLDER = "C:/TerminalAI"
else:
    # Fallback for unknown platforms
    CACHE_FOLDER = "/opt/TerminalAI"

CONFIG_FILE = os.path.join(CACHE_FOLDER, "config.ini")
COMMAND_HISTORY_FILE = os.path.join(CACHE_FOLDER, "command_history.pkl")

def get_config():
    """Reads and returns the configuration from config.ini."""
    config = configparser.ConfigParser()
    # To preserve case
    config.optionxform = str
    
    # ensure cache folder exists
    if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
        os.makedirs(os.path.expanduser(CACHE_FOLDER))
            
    config.read(CONFIG_FILE)
    return config

def save_config(config):
    """Saves the configuration to config.ini."""
    with open(CONFIG_FILE, 'w') as configfile:
        config.write(configfile)


def cache(maxsize=128):
    def decorator(func):
        def wrapper(*args, **kwargs):
            # Bypass the cache if env var is set
            if os.environ.get("NOCACHE"):
                return func(*args, **kwargs)
            key = str(args) + str(kwargs)

            # create the cache directory if it doesn't exist
            if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
                os.mkdir(os.path.expanduser(CACHE_FOLDER))

            # load the cache
            try:
                cache_folder = os.path.expanduser(CACHE_FOLDER)
                with open(os.path.join(cache_folder, "cache.pkl"), "rb") as f:
                    cache = pickle.load(f)
            except (FileNotFoundError, EOFError):
                cache = OrderedDict()

            if not isinstance(cache, OrderedDict):
                cache = OrderedDict()

            if key in cache:
                return cache[key]
            else:
                result = func(*args, **kwargs)
                if len(cache) >= maxsize:
                    # remove the oldest entry
                    cache.popitem(last=False)

                cache[key] = result
                cache_folder = os.path.expanduser(CACHE_FOLDER)
                with open(os.path.join(cache_folder, "cache.pkl"), "wb") as f:
                    pickle.dump(cache, f)
                return result

        return wrapper

    return decorator


def get_api_key():
    config = get_config()
    if not config.has_section('API'):
        config.add_section('API')

    api_key = config.get('API', 'key', fallback=None)
    
    if not api_key:
        print("No API key found in " + CONFIG_FILE)
        api_key = input("Please enter your OpenAI API key: ")
        if not api_key:
            print("No API key provided. Exiting.")
            sys.exit(1)
        config.set('API', 'key', api_key)
        save_config(config)

    return api_key


def get_api_base_url():
    config = get_config()
    return config.get('API', 'base_url', fallback=None)


def get_model_name():
    config = get_config()
    return config.get('Settings', 'model', fallback='gpt-4o-mini')


def get_safety_mode():
    config = get_config()
    try:
        mode = config.getint('Settings', 'safety_mode', fallback=0)
        return mode if mode in [0, 1] else 0
    except (ValueError, configparser.NoSectionError):
        return 0


def get_autocorrect_mode():
    """Reads the auto-correct setting from config.ini."""
    config = get_config()
    try:
        return config.getboolean('Settings', 'autocorrect', fallback=False)
    except (ValueError, configparser.NoSectionError):
        return False


def get_multi_step_mode():
    """Reads the multi-step execution setting from config.ini."""
    config = get_config()
    try:
        return config.getboolean('Settings', 'multi_step', fallback=False)
    except (ValueError, configparser.NoSectionError):
        return False


def analyze_command_safety(cmd):
    """
    Analyzes a command for safety risks
    Returns: (is_safe, reason)
    - is_safe: boolean, True if command is considered safe
    - reason: string explaining the safety assessment
    """
    # Read patterns from files
    dangerous_patterns = []
    safe_patterns = []
    
    # Try to read dangerous patterns from file
    try:
        with open("dangerous_patterns.txt", "r") as f:
            dangerous_patterns = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        print("Warning: dangerous_patterns.txt not found. Command safety checks will be limited.")
    
    # Try to read safe patterns from file
    try:
        with open("safe_patterns.txt", "r") as f:
            safe_patterns = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        print("Warning: safe_patterns.txt not found. Command safety checks will be limited.")

    # First check if it's a known safe command
    for pattern in safe_patterns:
        if re.search(pattern, cmd, re.IGNORECASE):
            return True, "Command appears to be safe (basic system information or navigation)"
    
    # Then check for dangerous patterns
    for pattern in dangerous_patterns:
        if re.search(pattern, cmd, re.IGNORECASE):
            return False, f"Command contains potentially dangerous pattern: {pattern}"
    
    # Check for pipe to shell
    if "|" in cmd and any(shell in cmd.lower() for shell in ["sh", "bash", "powershell", "cmd", "invoke-expression", "iex"]):
        return False, "Command pipes output to a shell, which could be dangerous"
    
    # Check for redirection to system files
    if ">" in cmd and any(path in cmd.lower() for path in ["/etc", "/bin", "/sbin", "/usr", "c:\\windows", "%windir%", "system32"]):
        return False, "Command redirects output to system directories"
    
    # Check for commands that might download or execute code
    if any(cmd.lower().startswith(download) for download in ["wget", "curl", "invoke-webrequest", "start-bitstransfer"]):
        return False, "Command downloads content from the internet"
    
    # If no dangerous patterns found, consider it moderately safe
    return True, "No obvious dangerous patterns detected"


def setup_api_configuration():
    """Interactive setup for API key and base URL using config.ini"""
    config = get_config()

    print("\n=== TerminalAI Configuration (config.ini) ===")
    
    # Ensure sections exist
    if not config.has_section('API'):
        config.add_section('API')
    if not config.has_section('Settings'):
        config.add_section('Settings')

    # Current values
    current_key = config.get('API', 'key', fallback='')
    current_base_url = config.get('API', 'base_url', fallback='')
    current_model = config.get('Settings', 'model', fallback='gpt-4o-mini')
    current_safety_mode = get_safety_mode()
    current_autocorrect_mode = get_autocorrect_mode()
    current_multi_step_mode = get_multi_step_mode()

    print(f"Current API key: {current_key[:4]}...{current_key[-4:] if len(current_key) > 8 else ''}")
    print(f"Current API base URL: {current_base_url if current_base_url else 'Default (OpenAI)'}")
    print(f"Current model: {current_model}")
    safety_mode_desc = "Always ask for confirmation" if current_safety_mode == 0 else "Auto-run safe commands"
    print(f"Current safety mode: {safety_mode_desc}")
    autocorrect_desc = "Enabled" if current_autocorrect_mode else "Disabled"
    print(f"Current auto-correct mode: {autocorrect_desc}")
    multi_step_desc = "Enabled" if current_multi_step_mode else "Disabled"
    print(f"Current multi-step mode: {multi_step_desc}")
    
    print("\nOptions:")
    print("1. Update API key")
    print("2. Update API base URL (for OpenAI-compatible APIs)")
    print("3. Update model name")
    print("4. Update safety mode")
    print("5. Update auto-correct on failure")
    print("6. Update multi-step commands")
    print("7. Reset to OpenAI defaults")
    print("8. Exit")
    
    choice = input("\nSelect option (1-8): ").strip()
    
    if choice == "1":
        new_key = input("Enter new API key: ").strip()
        if new_key:
            config.set('API', 'key', new_key)
            save_config(config)
            print("API key updated!")
        else:
            print("API key not changed.")
    
    elif choice == "2":
        print("\nPopular OpenAI-compatible APIs:")
        print("- OpenAI: https://api.openai.com/v1 (default)")
        print("- Azure OpenAI: https://your-resource.openai.azure.com/")
        print("- LocalAI: http://localhost:8080/v1")
        print("- Ollama: http://localhost:11434/v1")
        print("- LM Studio: http://localhost:1234/v1")
        
        new_base_url = input("\nEnter API base URL (leave empty for OpenAI default): ").strip()
        if new_base_url:
            config.set('API', 'base_url', new_base_url)
            print(f"API base URL set to: {new_base_url}")
        elif config.has_option('API', 'base_url'):
            config.remove_option('API', 'base_url')
            print("API base URL reset to OpenAI default.")
        save_config(config)

    elif choice == "3":
        print("\nPopular models by provider:")
        print("OpenAI:")
        print("  - gpt-4o-mini (default, cost-effective)")
        print("  - gpt-4o (latest, most capable)")
        print("  - gpt-4-turbo")
        print("  - gpt-3.5-turbo")
        print("\nLocalAI/Ollama:")
        print("  - llama3.2:3b")
        print("  - llama3.1:8b")
        print("  - codellama:7b")
        print("  - mistral:7b")
        print("\nAzure OpenAI:")
        print("  - Use your deployment name")
        
        new_model = input(f"\nEnter model name (current: {current_model}): ").strip()
        if new_model:
            config.set('Settings', 'model', new_model)
            save_config(config)
            print(f"Model set to: {new_model}")
        else:
            print("Model not changed.")
    
    elif choice == "4":
        print("\nSafety Modes:")
        print("0 - Always ask for confirmation before executing commands (default)")
        print("1 - Auto-run commands that appear safe, ask for confirmation on potentially dangerous commands")
        
        try:
            new_mode_str = input("\nEnter safety mode (0 or 1): ").strip()
            new_mode = int(new_mode_str)
            if new_mode in [0, 1]:
                config.set('Settings', 'safety_mode', str(new_mode))
                save_config(config)
                mode_desc = "Always ask for confirmation" if new_mode == 0 else "Auto-run safe commands"
                print(f"Safety mode set to: {mode_desc}")
            else:
                print("Invalid mode. Safety mode not changed.")
        except ValueError:
            print("Invalid input. Safety mode not changed.")
    
    elif choice == "5":
        print("\nAuto-correct on Failure:")
        print("Enable this to let AI try to fix commands that fail.")
        
        try:
            enable_str = input(f"Enable auto-correct? (currently {'Enabled' if current_autocorrect_mode else 'Disabled'}) [y/n]: ").strip().lower()
            if enable_str in ['y', 'yes']:
                config.set('Settings', 'autocorrect', 'True')
                save_config(config)
                print("Auto-correct enabled.")
            elif enable_str in ['n', 'no']:
                config.set('Settings', 'autocorrect', 'False')
                save_config(config)
                print("Auto-correct disabled.")
            else:
                print("Invalid input. Setting not changed.")
        except Exception as e:
            print(f"An error occurred: {e}")
    
    elif choice == "6":
        print("\nMulti-Step Commands:")
        print("Enable this to allow the AI to generate a sequence of commands for complex tasks.")
        
        try:
            enable_str = input(f"Enable multi-step commands? (currently {'Enabled' if current_multi_step_mode else 'Disabled'}) [y/n]: ").strip().lower()
            if enable_str in ['y', 'yes']:
                config.set('Settings', 'multi_step', 'True')
                save_config(config)
                print("Multi-step commands enabled.")
            elif enable_str in ['n', 'no']:
                config.set('Settings', 'multi_step', 'False')
                save_config(config)
                print("Multi-step commands disabled.")
            else:
                print("Invalid input. Setting not changed.")
        except Exception as e:
            print(f"An error occurred: {e}")
    
    elif choice == "7":
        # Reset to defaults
        if config.has_option('API', 'base_url'):
            config.remove_option('API', 'base_url')
        config.set('Settings', 'model', 'gpt-4o-mini')
        config.set('Settings', 'safety_mode', '0')
        config.set('Settings', 'autocorrect', 'False')
        config.set('Settings', 'multi_step', 'False')
        save_config(config)
        print("Reset to OpenAI defaults (gpt-4o-mini, always ask, auto-correct off, multi-step off). API key kept unchanged.")
    
    elif choice == "8":
        print("Exiting configuration menu.")
    
    else:
        print("Invalid choice. Exiting configuration menu.")
    
    print("=" * 35)


def get_context_files():
    """
    Gets context from files in the current directory.
    It lists all files and reads the content of important project files.
    """
    IMPORTANT_FILES = [
        'docker-compose.yml', 'docker-compose.yaml', 'Dockerfile',
        'package.json', 'requirements.txt', 'pom.xml', 'build.gradle',
        'Makefile', '.gitlab-ci.yml', '.travis.yml', 'pyproject.toml'
    ]
    MAX_CONTENT_LENGTH = 2000  # Max characters to read from each important file

    context_prompt = ""
    try:
        files_in_dir = os.listdir(os.getcwd())
        context_prompt += "The command is executed in a folder containing the following files:\n%s\n" % ", ".join(files_in_dir)

        for filename in files_in_dir:
            if filename in IMPORTANT_FILES:
                try:
                    with open(filename, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read(MAX_CONTENT_LENGTH)
                        context_prompt += f"\nThe content of '{filename}' is:\n---
{content}\n"
                        if len(content) == MAX_CONTENT_LENGTH:
                            context_prompt += "... (file content truncated)\n"
                        context_prompt += "---\n"
                except Exception as e:
                    log.warning(f"Could not read content of {filename}: {e}")
    except Exception as e:
        log.error(f"Could not list directory to create context: {e}")
    
    return context_prompt


def get_context_process_list():
    context_prompt = ""
    # list all processes
    if PLATFORM == "Windows":
        try:
            process_list = subprocess.check_output(["tasklist", "/fo", "csv"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            process_list = subprocess.check_output(["wmic", "process", "get", "ProcessId,ParentProcessId,CommandLine", "/format:csv"], shell=True).decode("utf-8")
    else:
        process_list = subprocess.check_output(["ps", "-A", "-o", "pid,ppid,cmd"]).decode("utf-8")
    context_prompt += "The following processes are running: %s\n" % process_list
    return context_prompt


def get_context_env():
    context_prompt = ""
    # list all environment variables
    env = os.environ
    context_prompt += "The following environment variables are set: %s\n" % env
    return context_prompt


def get_context_users():
    context_prompt = ""
    # list all users
    if PLATFORM == "Windows":
        try:
            users = subprocess.check_output(["net", "user"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            users = subprocess.check_output(["wmic", "useraccount", "get", "Name,Description", "/format:csv"], shell=True).decode("utf-8")
    else:
        users = subprocess.check_output(["getent", "passwd"]).decode("utf-8")
    context_prompt += "The following users are defined: %s\n" % users
    return context_prompt


def get_context_groups():
    context_prompt = ""
    # list all groups
    if PLATFORM == "Windows":
        try:
            groups = subprocess.check_output(["net", "localgroup"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            groups = subprocess.check_output(["wmic", "group", "get", "Name,Description", "/format:csv"], shell=True).decode("utf-8")
    else:
        groups = subprocess.check_output(["getent", "group"]).decode("utf-8")
    context_prompt += "The following groups are defined: %s\n" % groups
    return context_prompt


def get_context_network_interfaces():
    context_prompt = ""
    # list all network interfaces
    if PLATFORM == "Windows":
        try:
            interfaces = subprocess.check_output(["ipconfig", "/all"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            interfaces = subprocess.check_output(["wmic", "path", "win32_networkadapter", "get", "Name,MACAddress", "/format:csv"], shell=True).decode("utf-8")
    else:
        interfaces = subprocess.check_output(["ip", "link"]).decode("utf-8")
    context_prompt += "The following network interfaces are defined: %s\n" % interfaces
    return context_prompt


def get_context_network_routes():
    context_prompt = ""
    # list all network routes
    if PLATFORM == "Windows":
        try:
            routes = subprocess.check_output(["route", "print"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            routes = subprocess.check_output(["netstat", "-rn"], shell=True).decode("utf-8")
    else:
        routes = subprocess.check_output(["ip", "route"]).decode("utf-8")
    context_prompt += "The following network routes are defined: %s\n" % routes
    return context_prompt


def get_context_iptables():
    context_prompt = ""
    # list all firewall rules
    if PLATFORM == "Windows":
        try:
            firewall = subprocess.check_output(["netsh", "advfirewall", "firewall", "show", "rule", "name=all"], shell=True).decode("utf-8")
        except subprocess.CalledProcessError:
            firewall = "Firewall rules not accessible"
    else:
        try:
            firewall = subprocess.check_output(["sudo", "iptables", "-L"]).decode("utf-8")
        except subprocess.CalledProcessError:
            firewall = "iptables not accessible"
    context_prompt += "The following firewall rules are defined: %s\n" % firewall
    return context_prompt


CONTEXT = [
    {"name": "List of files in the current directory", "function": get_context_files},
    {"name": "List of processes", "function": get_context_process_list},
    # {"name": "List of environment variables", "function": get_context_env}, # This looks like a security issue
    {"name": "List of users", "function": get_context_users},
    {"name": "List of groups", "function": get_context_groups},
    {"name": "List of network interfaces", "function": get_context_network_interfaces},
    {"name": "List of network routes", "function": get_context_network_routes},
    {"name": "List of iptables rules", "function": get_context_iptables},
]


def load_history():
    # create the cache directory if it doesn't exist
    if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
        os.mkdir(os.path.expanduser(CACHE_FOLDER))

    # load the history from .chat_history
    cache_folder = os.path.expanduser(CACHE_FOLDER)
    path = os.path.join(cache_folder, "chat_history")
    if os.path.exists(path):
        with open(path, "rb") as f:
            history = pickle.load(f)
    else:
        history = []
    return history


def save_history(history, limit=50):
    # create the cache directory if it doesn't exist
    if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
        os.mkdir(os.path.expanduser(CACHE_FOLDER))

    # save the history to chat_history
    cache_folder = os.path.expanduser(CACHE_FOLDER)
    with open(os.path.join(cache_folder, "chat_history"), "wb") as f:
        history = history[-limit:]
        pickle.dump(history, f)


def clean_history():
    # create the cache directory if it doesn't exist
    if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
        os.mkdir(os.path.expanduser(CACHE_FOLDER))

    cache_folder = os.path.expanduser(CACHE_FOLDER)
    path = os.path.join(cache_folder, "chat_history")
    if os.path.exists(path):
        os.unlink(path)


def get_powershell_history_path():
    """Gets the PowerShell history file path dynamically."""
    # This function is only relevant on Windows.
    if PLATFORM != "Windows":
        return None
    
    try:
        # Use PowerShell to get the correct history path from PSReadLine
        ps_command = "(Get-PSReadlineOption).HistorySavePath"
        # Using -NoProfile for a faster and cleaner execution
        path = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", ps_command], 
            text=True, 
            stderr=subprocess.DEVNULL
        ).strip()
        
        # If the command returns an empty string, PSReadLine might not be configured to save history.
        if not path:
            log.warning("PSReadLine HistorySavePath is not set. Falling back to default path.")
            return os.path.expanduser("~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt")
            
        return path
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback to the default path in case of any error (e.g., powershell not in PATH or PSReadLine module not available)
        log.warning("Could not dynamically determine PowerShell history path. Falling back to default.")
        return os.path.expanduser("~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt")


def chat(client, prompt):
    history = load_history()
    # esitmate the length of the history in words
    while sum([len(h["content"].split()) for h in history]) > 2000:
        # skip the first message that should be the system message
        history = history[1:]

    print("History length: %s" % sum([len(h["content"].split()) for h in history]))

    if len(history) == 0 or len([h for h in history if h["role"] == "system"]) == 0:
        if PLATFORM == "Windows":
            import platform
            distribution = f"Windows {platform.release()}"
            system_message = f"You are a helpful assistant. Answer as concisely as possible. This machine is running Windows {platform.release()}. When suggesting commands, use Windows PowerShell or CMD commands, NOT Linux/Unix commands."
        else:
            if distro:
                distribution = distro.name()
                system_message = f"You are a helpful assistant. Answer as concisely as possible. This machine is running {PLATFORM} {distribution}."
            else:
                distribution = "Linux"
                system_message = f"You are a helpful assistant. Answer as concisely as possible. This machine is running {PLATFORM}."
        history.append(
            {
                "role": "system",
                "content": system_message
            }
        )

    history.append({"role": "user", "content": prompt})
    model_name = get_model_name()
    response = client.chat.completions.create(model=model_name, messages=history)
    
    # Check if response is valid
    if not response.choices or not response.choices[0].message.content:
        content = "Error: Empty response from API. Please check your model and API configuration."
    else:
        content = response.choices[0].message.content
        # trim the content
        content = content.strip()
    
    history.append({"role": "assistant", "content": content})
    save_history(history)
    return content


@cache()
def get_cmd(client, prompt, context_prompt=""):
    # add info about the system to the prompt. E.g. ubuntu, arch, etc.
    if PLATFORM == "Windows":
        import platform
        distribution = f"Windows {platform.release()}"
        system_info = f"Windows {platform.release()}. Use Windows PowerShell or CMD commands, not Linux/Unix commands."
    else:
        if distro:
            distribution = distro.like()
            if distribution is None or distribution == "":
                distribution = distro.name()
            system_info = f"{PLATFORM} like {distribution}"
        else:
            distribution = "Linux"
            system_info = f"{PLATFORM}"
    log.debug("Distribution: %s" % distribution)

    multi_step_enabled = get_multi_step_mode()
    if multi_step_enabled:
        system_message_content = f"You can output a sequence of terminal commands separated by newlines. No info! No comments. No backticks. This system is running on {system_info}. If the user's request requires multiple steps (e.g., 'clone a repo, cd into it, and run npm install'), provide each command on a new line. Otherwise, provide a single command."
        user_message_content = "Generate the necessary command(s) to %s\n%s" % (prompt, context_prompt)
    else:
        system_message_content = f"You can output only a single terminal command! No info! No comments. No backticks. This system is running on {system_info}. If on Windows, use PowerShell or CMD commands, NOT Linux/Unix commands."
        user_message_content = "Generate a single bash command to %s\n%s" % (prompt, context_prompt)

    model_name = get_model_name()
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": system_message_content},
            {"role": "user", "content": user_message_content},
        ],
        max_tokens=250,
        temperature=0,
        top_p=1,
    )
    
    # Check if response is valid
    if not response.choices or not response.choices[0].message.content:
        print("Error: Empty response from API. Please check your model and API configuration.")
        print(f"Model: {model_name}")
        print(f"API Base URL: {get_api_base_url() or 'Default (OpenAI)'}")
        return "echo 'Error: No command generated'"
    
    cmd = response.choices[0].message.content

    # sanitize backticks and "```bash"
    cmd = cmd.replace("```bash\n", "").replace("\n```", "")

    # trim the cmd
    cmd = cmd.strip()
    return cmd


@cache()
def get_cmd_list(client, prompt, context_files=[], n=5):
    # add info about the system to the prompt. E.g. ubuntu, arch, etc.
    if PLATFORM == "Windows":
        import platform
        distribution = f"Windows {platform.release()}"
        system_info = f"Windows {platform.release()}. Use Windows PowerShell or CMD commands, not Linux/Unix commands."
    else:
        if distro:
            distribution = distro.like()
            if distribution is None or distribution == "":
                distribution = distro.name()
            system_info = f"{PLATFORM} like {distribution}"
        else:
            distribution = "Linux"
            system_info = f"{PLATFORM}"
    log.debug("Distribution: %s" % distribution)
    context_prompt = get_context_files()

    model_name = get_model_name()
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": f"You can output only terminal commands! No info! No comments. No backticks. Running on {system_info}. {context_prompt} If on Windows, use PowerShell or CMD commands, NOT Linux/Unix commands."},
            {"role": "user", "content": "Generate a single bash command to %s" % prompt},
        ],
        max_tokens=50,
        temperature=0.9,
        top_p=1,
        n=n,
    )
    
    # Check if response is valid
    if not response.choices:
        print("Error: Empty response from API for command list generation.")
        return ["echo 'Error: No commands generated'"]
    
    cmd_list = []
    for choice in response.choices:
        if choice.message.content:
            content = choice.message.content.replace("```bash\n", "").replace("\n```", "")
            cmd_list.append(content.strip())
    
    if not cmd_list:
        return ["echo 'Error: No valid commands generated'"]
    
    # trim the cmd and remove duplicates
    cmd_list = list(set([x for x in cmd_list if x]))
    return cmd_list


@cache()
def get_needed_context(cmd, client):
    context_list = ""
    for i in range(len(CONTEXT)):
        context_list += "%s ) %s\n" % (i, CONTEXT[i]["name"])

    prompt = (
        "If you need to generate a single terminal command to %s, which of this context you need:\n%s\n Your output is a number.\n If none of the above context is usefull the output is -1.\n"
        % (cmd, context_list)
    )

    model_name = get_model_name()
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": "You can output only a number."},
            {"role": "user", "content": prompt},
        ],
        max_tokens=4,
        temperature=0,
        top_p=1,
    )
    choice = response.choices[0].message.content.strip()
    try:
        choice = int(choice.strip())
    except:
        # print the wrong chice in red
        print("Wrong context: \033[1;31m%s\033[0m" % choice)
        choice = -1

    return choice


@cache()
def get_explaination(client, cmd):
    model_name = get_model_name()
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": "Explain what is the purpose of command with details for each option."},
            {"role": "user", "content": cmd},
        ],
        max_tokens=250,
        temperature=0,
        top_p=1,
    )
    
    # Check if response is valid
    if not response.choices or not response.choices[0].message.content:
        return "Error: Could not generate explanation. Please check your model and API configuration."
    
    explanation = response.choices[0].message.content
    explanation = explanation.replace("\n\n", "\n")
    return explanation


def highlight(cmd, explanation):
    for x in set(cmd.split(" ")):
        x_strip = x.strip()
        x_replace = "\033[1;33m%s\033[0m" % x_strip

        # escape the special characters
        x_strip = re.escape(x_strip)

        explanation = re.sub(
            r"([\s'\"`\.,;:])%s([\s'\"`\.,;:])" % x_strip,
            "\\1%s\\2" % x_replace,
            explanation,
        )
    return explanation


def square_text(text):
    # retrieve the terminal size using library
    columns, lines = os.get_terminal_size(0)

    # set mono spaced font
    out = "\033[10m"

    out = "-" * int(columns)
    for line in text.split("\n"):
        for i in range(0, len(line), int(columns) - 4):
            out += "\n| %s |" % line[i : i + int(columns) - 4].ljust(int(columns) - 4)
    out += "\n" + "-" * int(columns)
    return out


def print_explaination(client, cmd):
    explaination = get_explaination(client, cmd)
    h_explaination = highlight(cmd, square_text(explaination.strip()))
    print("-" * 27)
    print("| *** \033[1;31m Explaination: \033[0m *** |")
    print(h_explaination)
    print("")


def generate_context_help():
    c_string = ""
    for i in range(len(CONTEXT)):
        c_string += "\t%s) %s\n" % (i, CONTEXT[i]["name"])
    return c_string


# Control-C to exit
def signal_handler(sig, frame):
    print("\nExiting.")
    sys.exit(0)


def load_command_history():
    """Loads the command history."""
    if not os.path.exists(COMMAND_HISTORY_FILE):
        return []
    try:
        with open(COMMAND_HISTORY_FILE, "rb") as f:
            history = pickle.load(f)
            return history if isinstance(history, list) else []
    except (EOFError, pickle.UnpicklingError):
        return []

def save_command_history(history, limit=100):
    """Saves the command history."""
    with open(COMMAND_HISTORY_FILE, "wb") as f:
        history = history[-limit:]
        pickle.dump(history, f)

def add_to_command_history(command):
    """Adds a successfully executed command to the history."""
    history = load_command_history()
    # Avoid adding the same command consecutively
    if not history or history[-1] != command:
        history.append(command)
        save_command_history(history)


def manage_command_history():
    """Displays command history and allows re-execution."""
    history = load_command_history()
    if not history:
        print("Command history is empty.")
        return

    print("\n--- AI Command History ---")
    for i, cmd in enumerate(history):
        print(f"{i+1: >3}: {cmd}")
    print("--------------------------")

    try:
        choice = input("Enter a number to re-run a command, or 'q' to quit: ").strip()
        if choice.lower() == 'q' or not choice:
            return
        
        choice_idx = int(choice) - 1
        if 0 <= choice_idx < len(history):
            cmd_to_run = history[choice_idx]
            print(f"Selected command: \033[1;32m{cmd_to_run}\033[0m")
            if input("Execute this command? [Y/n] ").lower() != 'n':
                # Determine shell
                if PLATFORM == "Windows":
                    shell = os.environ.get("COMSPEC", "cmd.exe")
                    shell_type = "powershell" if "powershell" in os.environ.get("PSModulePath", "").lower() or "powershell" in shell.lower() else "cmd"
                else:
                    shell = os.environ.get("SHELL", "/bin/bash")
                    shell_type = "unix"

                result = execute_and_handle_history(cmd_to_run, shell_type, shell)
                
                if result.stdout:
                    print(result.stdout, end='')
                if result.stderr:
                    print(f"\033[1;31m{result.stderr}\033[0m", file=sys.stderr, end='')

                if result.returncode == 0:
                    print("\n\033[1;32mCommand executed successfully.\033[0m")
                    add_to_command_history(cmd_to_run) # Add again to bring it to the top
                else:
                    print(f"\n\033[1;31mCommand failed with exit code {result.returncode}.\033[0m")
            else:
                print("Execution cancelled.")
        else:
            print("Invalid selection.")
    except ValueError:
        print("Invalid input. Please enter a number.")
    except (KeyboardInterrupt, EOFError):
        print("\nExiting history menu.")


def execute_and_handle_history(cmd, shell_type, shell):
    """Saves a command to history and then executes it, capturing output."""
    if not os.environ.get("NOHISTORY"):
        # retrieve the history file of the shell depending on the shell
        if PLATFORM == "Windows":
            if shell_type == "powershell":
                # PowerShell history
                history_file = get_powershell_history_path()
                new_history_line = f"{cmd}\n"
            else:
                # CMD doesn't have persistent history by default
                history_file = None
                new_history_line = None
        else:
            if "/bin/bash" in shell:
                history_file = os.path.expanduser("~/.bash_history")
                new_history_line = f"{cmd}\n"
            elif "/bin/zsh" in shell:
                history_file = os.environ.get("HISTFILE", os.path.expanduser("~/.zsh_history")) 
                
                # Get UNIX timestamp
                timestamp = int(time.time())
                new_history_line = f": {int(timestamp)}:0;{cmd}\n"
            elif "/bin/fish" in shell:
                # Untested
                history_file = os.path.expanduser("~/.local/share/fish/fish_history")
                new_history_line = f"{cmd}\n"
            else:
                history_file = None
                new_history_line = None
                # log.warning("Shell %s not supported. History will not be saved." % shell)

        # save the command to the history
        if history_file is not None and new_history_line is not None:
            try:
                # Ensure directory exists for PowerShell history
                if PLATFORM == "Windows" and shell_type == "powershell":
                    os.makedirs(os.path.dirname(history_file), exist_ok=True)
                with open(history_file, "a", encoding="utf-8") as f:
                    f.write(new_history_line)
            except IOError as e:
                log.error("Failed to save history: %s" % e)

    # Execute the command in the current shell and return the result
    try:
        if PLATFORM == "Windows":
            if shell_type == "powershell":
                return subprocess.run(["powershell", "-Command", cmd], shell=False, capture_output=True, text=True, encoding='utf-8', errors='ignore')
            else:
                return subprocess.run(cmd, shell=True, capture_output=True, text=True, encoding='utf-8', errors='ignore')
        else:
            return subprocess.run(cmd, shell=True, executable=shell, capture_output=True, text=True, encoding='utf-8', errors='ignore')
    except FileNotFoundError:
        # This can happen if the command itself is not found, e.g. "mydoesnotexist"
        # We can create a mock result object to handle this gracefully.
        return subprocess.CompletedProcess(args=cmd, returncode=127, stdout="", stderr=f"Command not found: {cmd.split()[0]}")


if __name__ == "__main__":
    
    # get the command from the user
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "-c", action="store_true", help="auto select context to be included."
    )
    parser.add_argument(
        "-C",
        action="store",
        type=int,
        default=-1,
        choices=range(0, len(CONTEXT)),
        help="specify which context to include: %s" % generate_context_help(),
    )
    parser.add_argument(
        "-e", action="store_true", help="explain the generated command."
    )
    parser.add_argument(
        "-n",
        action="store",
        type=int,
        default=5,
        help="number of commands to generate.",
    )
    parser.add_argument("--chat", action="store_true", help="Chat mode.")
    parser.add_argument("--new", action="store_true", help="Clean the chat history.")
    parser.add_argument("--config", action="store_true", help="Configure API key and base URL.")
    parser.add_argument("--history", action="store_true", help="Show command history and re-run commands.")
    parser.add_argument("text", nargs="*", help="your query to the ai")

    args = parser.parse_args()

    # Handle configuration mode
    if args.config:
        setup_api_configuration()
        sys.exit(0)

    # Check if we have a query (only when not in chat mode)
    if not args.chat and not args.text and not args.history:
        print("Please provide a command to execute or use --config or --history.")
        print("Examples:")
        print("  ai list all files")
        print("  ai --chat")
        print("  ai --config")
        sys.exit(1)

    # get the prompt
    prompt = " ".join(args.text) if args.text else ""

    # setup control-c handler
    signal.signal(signal.SIGINT, signal_handler)

    # get the api key
    api_key = get_api_key()

    if openai is None:
        print("Error: openai package is not installed. Please run: pip install openai")
        sys.exit(1)

    # Get API configuration
    base_url = get_api_base_url()
    model_name = get_model_name()
    
    if base_url:
        print(f"Using custom API base URL: {base_url}")
        client = openai.OpenAI(api_key=api_key, base_url=base_url)
    else:
        client = openai.OpenAI(api_key=api_key)
    
    print(f"Using model: {model_name}")

    # Handle history mode
    if args.history:
        manage_command_history()
        sys.exit(0)

    context = args.c or args.C >= 0
    context_files = []
    context_prompt = ""
    if context:
        needed_contxt = args.C
        if needed_contxt < 0:
            needed_contxt = get_needed_context(prompt, client)
        if needed_contxt >= 0:
            print("AI choose to %s as context." % CONTEXT[needed_contxt]["name"])
            context_prompt += CONTEXT[needed_contxt]["function"]()
        if len(context_prompt) > 3000:
            context_prompt = context_prompt[:3000]

    if args.chat:
        if args.new:
            print("Cleaning the chat history.")
            clean_history()
        while True:
            cmd = chat(client, prompt)
            print("AI: %s" % cmd)
            prompt = input("You: ")
        sys.exit(0)

    # get the command from the ai
    cmd_or_sequence = get_cmd(client, prompt, context_prompt=context_prompt)
    commands = [c.strip() for c in cmd_or_sequence.split('\n') if c.strip()]

    if not commands:
        print("Error: AI did not return a valid command.")
        sys.exit(1)

    # retrieve the shell
    if PLATFORM == "Windows":
        shell = os.environ.get("COMSPEC", "cmd.exe")
        # Check if running in PowerShell
        if "powershell" in os.environ.get("PSModulePath", "").lower() or "powershell" in shell.lower():
            shell_type = "powershell"
        else:
            shell_type = "cmd"
    else:
        shell = os.environ.get("SHELL")
        # if no shell is set, use bash
        if shell is None:
            shell = "/bin/bash"
        shell_type = "unix"

    # Handle single command case
    if len(commands) == 1:
        cmd = commands[0]
        if args.e:
            print_explaination(client, cmd)

        # print the command colorized
        print("AI wants to execute \n\033[1;32m%s\033[0m\n" % cmd)

        # Analyze command safety
        is_safe, safety_reason = analyze_command_safety(cmd)
        safety_mode = get_safety_mode()
        
        # Show safety assessment
        if is_safe:
            print(f"Safety assessment: \033[1;32mSafe\033[0m - {safety_reason}")
        else:
            print(f"Safety assessment: \033[1;31mPotentially dangerous\033[0m - {safety_reason}")
        
        # Determine if we need user confirmation
        need_confirmation = True
        if safety_mode == 1 and is_safe:
            need_confirmation = False
            print("Auto-executing safe command (safety mode: auto-run safe commands)")
        
        # validate the command
        if need_confirmation and input("Do you want to execute this command? [Y/n] ").lower() == "n":
            # execute the command with Popen and save it to the history
            cmds = get_cmd_list(client, prompt, context_files=context_files, n=args.n)
            print("Here are some other commands you might want to execute:")
            index = 0
            for cmd_alt in cmds:
                print("%d. \033[1;32m%s\033[0m" % (index, cmd_alt))
                # Analyze alternative command safety
                alt_is_safe, alt_safety_reason = analyze_command_safety(cmd_alt)
                if alt_is_safe:
                    print(f"   Safety: \033[1;32mSafe\033[0m - {alt_safety_reason}")
                else:
                    print(f"   Safety: \033[1;31mPotentially dangerous\033[0m - {alt_safety_reason}")
                    
                if args.e:
                    print_explaination(client, cmd_alt)
                    print("\n")

                index += 1

            choice = input(
                "Do you want to execute one of these commands? [0-%d] " % (index - 1)
            )
            if choice.isdigit() and int(choice) < index:
                cmd = cmds[int(choice)]
            else:
                print("No command executed.")
                sys.exit(1)
    
    # Handle multi-step command case
    else:
        print("AI wants to execute the following sequence of commands:")
        all_safe = True
        for i, c in enumerate(commands):
            is_safe, safety_reason = analyze_command_safety(c)
            if not is_safe:
                all_safe = False
            color = "\033[1;32m" if is_safe else "\033[1;31m"
            print(f"  {i+1}. {color}{c}\033[0m  ({safety_reason})")
        
        print("")
        
        safety_mode = get_safety_mode()
        need_confirmation = True
        if safety_mode == 1 and all_safe:
            need_confirmation = False
            print("Auto-executing safe command sequence (safety mode: auto-run safe commands)")

        if need_confirmation and input("Do you want to execute this entire sequence? [Y/n] ").lower() == "n":
            print("No commands executed.")
            sys.exit(1)
        
        for idx, cmd in enumerate(commands):
            print(f"\n--- Executing step {idx+1}/{len(commands)}: \033[1;32m{cmd}\033[0m ---")
            result = execute_and_handle_history(cmd, shell_type, shell)

            if result.stdout:
                print(result.stdout, end='')
            if result.stderr:
                print(f"\033[1;31m{result.stderr}\033[0m", file=sys.stderr, end='')

            if result.returncode != 0:
                print(f"\n\033[1;31mCommand failed with exit code {result.returncode}. Aborting sequence.\033[0m")
                sys.exit(result.returncode)
            else:
                # Add successful command to our history
                add_to_command_history(cmd)
        
        print("\n\033[1;32mSequence executed successfully.\033[0m")
        sys.exit(0)


    # Execute command, save history, and capture output
    result = execute_and_handle_history(cmd, shell_type, shell)

    if result.stdout:
        print(result.stdout, end='')
    if result.stderr:
        # Print stderr in red
        print(f"\033[1;31m{result.stderr}\033[0m", file=sys.stderr, end='')

    # Add to command history if successful
    if result.returncode == 0:
        add_to_command_history(cmd)

    # Check for failure and auto-correct if enabled
    autocorrect_mode = get_autocorrect_mode()
    if result.returncode != 0 and autocorrect_mode:
        print(f"\n\033[1;33mCommand failed with exit code {result.returncode}.\033[0m")
        # Only try to fix if there's an error message to provide context
        if result.stderr:
            print("AI is attempting to find a fix...")
            
            fixed_cmd = get_fixed_cmd(client, cmd, result.stderr)
            
            # Analyze fixed command safety
            is_safe, safety_reason = analyze_command_safety(fixed_cmd)
            if is_safe:
                print(f"Safety assessment: \033[1;32mSafe\033[0m - {safety_reason}")
            else:
                print(f"Safety assessment: \033[1;31mPotentially dangerous\033[0m - {safety_reason}")

            print(f"\nAI suggests the following fix:\n\033[1;32m{fixed_cmd}\033[0m\n")
            
            if input("Do you want to execute this command? [Y/n] ").lower() != "n":
                print("Executing fixed command...")
                fixed_result = execute_and_handle_history(fixed_cmd, shell_type, shell)
                if fixed_result.stdout:
                    print(fixed_result.stdout, end='')
                if fixed_result.stderr:
                    print(f"\033[1;31m{fixed_result.stderr}\033[0m", file=sys.stderr, end='')
                
                if fixed_result.returncode == 0:
                    print("\n\033[1;32mFixed command executed successfully.\033[0m")
                else:
                    print(f"\n\033[1;31mFixed command also failed with exit code {fixed_result.returncode}.\033[0m")
            else:
                print("No command executed.")
        else:
            print("Command failed but produced no error output. Cannot attempt a fix.")
