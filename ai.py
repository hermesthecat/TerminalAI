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


VERSION = "0.3.0"
PLATFORM = platform.system()
if PLATFORM == "Linux":
    CACHE_FOLDER = "~/.cache/terminalai"
elif PLATFORM == "Darwin":
    PLATFORM = "MacOSX"
    CACHE_FOLDER = "~/Library/Caches/terminalai"
elif PLATFORM == "Windows":
    CACHE_FOLDER = "~/AppData/Local/terminalai"
else:
    # Fallback for unknown platforms
    CACHE_FOLDER = "~/.terminalai"


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
    # load the api key from CACHE_FOLDER/openai
    config_file = os.path.expanduser(CACHE_FOLDER + "/openai")
    if os.path.exists(config_file):
        with open(config_file) as f:
            return f.read().strip()
    else:
        print("No api key found. Please create a file " + CACHE_FOLDER + "/openai with your api key in it.")
        # ask for key and store it
        api_key = input("Please enter your OpenAI API key: ")
        if api_key == "":
            print("No api key provided. Exiting.")
            sys.exit(1)
        # make sure the directory exists
        if not os.path.exists(os.path.expanduser(CACHE_FOLDER)):
            os.mkdir(os.path.expanduser(CACHE_FOLDER))
        with open(config_file, "w") as f:
            f.write(api_key)

        return api_key


def get_api_base_url():
    # load the api base url from CACHE_FOLDER/openai_base_url
    config_file = os.path.expanduser(CACHE_FOLDER + "/openai_base_url")
    if os.path.exists(config_file):
        with open(config_file) as f:
            base_url = f.read().strip()
            return base_url if base_url else None
    return None


def get_model_name():
    # load the model name from CACHE_FOLDER/openai_model
    config_file = os.path.expanduser(CACHE_FOLDER + "/openai_model")
    if os.path.exists(config_file):
        with open(config_file) as f:
            model = f.read().strip()
            return model if model else "gpt-4o-mini"
    return "gpt-4o-mini"


def get_safety_mode():
    # load safety mode from CACHE_FOLDER/openai_safety_mode
    # 0 = always ask (default), 1 = auto-run safe commands
    config_file = os.path.expanduser(CACHE_FOLDER + "/openai_safety_mode")
    if os.path.exists(config_file):
        with open(config_file) as f:
            try:
                mode = int(f.read().strip())
                return mode if mode in [0, 1] else 0
            except:
                return 0
    return 0


def analyze_command_safety(cmd):
    """
    Analyzes a command for safety risks
    Returns: (is_safe, reason)
    - is_safe: boolean, True if command is considered safe
    - reason: string explaining the safety assessment
    """
    # Read patterns from files or use defaults
    dangerous_patterns = []
    safe_patterns = []
    
    # Try to read dangerous patterns from file
    try:
        with open("dangerous_patterns.txt", "r") as f:
            dangerous_patterns = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        # Default dangerous patterns if file not found
        dangerous_patterns = [
            # System modification
            r"\brm\s+(-[rf]+\s+)?(\/|~|\$HOME|\${HOME}|\$USER|\${USER})",  # rm with root/home paths
            r"\bmv\s+.+\s+(\/|~|\$HOME|\${HOME}|\$USER|\${USER})",  # mv to sensitive locations
            r"\bdd\s+",  # dd commands
            r"\bformat\s+",  # format commands
            r"\bmkfs\s+",  # filesystem creation
            r"del\s+.*\/[QqSs]",  # Windows delete with /Q or /S flags
            r"Remove-Item\s+.*\s+-Recurse",  # PowerShell recursive delete
            r"Remove-Item\s+.*\s+-Force",  # PowerShell forced delete
            
            # Privilege escalation
            r"\bsudo\s+",  # sudo commands
            r"\bsu\s+",  # su commands
            r"\brunas\s+",  # Windows runas
            r"Start-Process\s+.*\s+-Verb\s+RunAs",  # PowerShell run as admin
            r"psexec\s+",  # PsExec tool
            
            # Remote execution
            r"\bssh\s+.+\s+-exec",  # ssh with exec
            r"\btelnet\s+",  # telnet
            r"Invoke-Command\s+.*\s+-ComputerName",  # PowerShell remote command
            r"Enter-PSSession\s+",  # PowerShell remote session
            
            # Network/firewall
            r"\biptables\s+-(A|D|P|F|X|Z|I|R)\s+",  # iptables modifications
            r"\bnetsh\s+firewall\s+",  # Windows firewall changes
            r"\bnetsh\s+advfirewall\s+",  # Windows advanced firewall
            r"\broute\s+add\s+",  # route modifications
            r"New-NetFirewallRule\s+",  # PowerShell firewall rule creation
            r"Set-NetFirewallRule\s+",  # PowerShell firewall rule modification
            
            # File permissions
            r"\bchmod\s+777\s+",  # chmod with 777
            r"\bchmod\s+[+]x\s+",  # chmod adding execute
            r"\bicacls\s+.*\s+\/grant\s+",  # Windows permission changes
            r"Set-Acl\s+",  # PowerShell ACL modification
            r"Set-ItemProperty\s+",  # PowerShell item property modification
            
            # Process management
            r"\bkill\s+-9\s+",  # kill -9
            r"\bpkill\s+-9\s+",  # pkill -9
            r"\btaskkill\s+\/F\s+",  # forceful taskkill
            r"Stop-Process\s+.*\s+-Force",  # PowerShell forceful process termination
            
            # System configuration
            r"\bsystemctl\s+(stop|disable|mask)\s+",  # systemctl stopping services
            r"\bservice\s+.+\s+stop\s+",  # stopping services
            r"\bsc\s+stop\s+",  # Windows service stopping
            r"Stop-Service\s+",  # PowerShell service stopping
            r"Set-Service\s+",  # PowerShell service modification
            r"Disable-ComputerRestore\s+",  # Disable system restore
            
            # Registry modification (Windows)
            r"reg\s+(add|delete)\s+",  # Registry modification
            r"Set-ItemProperty\s+.*\s+HKLM:",  # PowerShell registry modification
            r"New-ItemProperty\s+.*\s+HKLM:",  # PowerShell registry creation
            r"Remove-ItemProperty\s+.*\s+HKLM:",  # PowerShell registry deletion
            
            # Downloading/executing
            r"curl\s+.+\s+\|\s+sh",  # piping curl to shell
            r"wget\s+.+\s+\|\s+sh",  # piping wget to shell
            r"curl\s+.+\s+\|\s+bash",  # piping curl to bash
            r"wget\s+.+\s+\|\s+bash",  # piping wget to bash
            r"powershell\s+-e\s+",  # encoded PowerShell
            r"powershell\s+.*\s+iex\s+",  # PowerShell invoke-expression
            r"powershell\s+.*\s+downloadstring\s+",  # PowerShell download and execute
            r"Invoke-Expression\s+",  # PowerShell execute string
            r"Invoke-WebRequest\s+.*\s+\|\s+Invoke-Expression",  # PowerShell download and execute
            r"Start-BitsTransfer\s+",  # PowerShell BITS transfer
            
            # Data exposure
            r"\bcat\s+.*\/(passwd|shadow|\.ssh\/|\.aws\/)",  # reading sensitive files
            r"\btype\s+.*\/(passwd|shadow|\.ssh\/|\.aws\/)",  # Windows reading sensitive files
            r"\bgrep\s+.*\/(passwd|shadow|\.ssh\/|\.aws\/)",  # grepping sensitive files
            r"Get-Content\s+.*\s+(password|credential|secret)",  # PowerShell reading sensitive files
            
            # System shutdown/restart
            r"\bshutdown\b",  # shutdown command
            r"\breboot\b",  # reboot command
            r"\bhalt\b",  # halt command
            r"\bpoweroff\b",  # poweroff command
            r"\binit\s+0\b",  # init 0 command
            r"\binit\s+6\b",  # init 6 command
            r"Stop-Computer\b",  # PowerShell shutdown
            r"Restart-Computer\b",  # PowerShell restart
            
            # Disk operations
            r"format\s+[a-zA-Z]:",  # Format drive
            r"diskpart\b",  # Disk partitioning
            r"fdisk\b",  # Disk partitioning
            r"Clear-Disk\b",  # PowerShell disk clearing
            
            # User management
            r"net\s+user\s+.*\s+\/add",  # Windows user addition
            r"net\s+localgroup\s+administrators\s+.*\s+\/add",  # Add to admin group
            r"New-LocalUser\b",  # PowerShell user creation
            r"Add-LocalGroupMember\b",  # PowerShell group modification
            r"Enable-LocalUser\b",  # PowerShell user enabling
            r"Disable-LocalUser\b",  # PowerShell user disabling
            
            # Scheduled tasks
            r"schtasks\s+\/create",  # Create scheduled task
            r"New-ScheduledTask\b",  # PowerShell scheduled task
            r"Register-ScheduledTask\b",  # PowerShell register task
            
            # System state
            r"wbadmin\s+start\s+",  # Windows Backup Admin
            r"vssadmin\s+delete\s+",  # Volume Shadow Copy deletion
            r"bcdedit\s+\/set\s+",  # Boot configuration changes
        ]
        # Create the file with default patterns for future use
        try:
            with open("dangerous_patterns.txt", "w") as f:
                f.write("# List of dangerous command patterns - one regex per line\n")
                f.write("# Lines starting with # are comments\n\n")
                for pattern in dangerous_patterns:
                    f.write(f"{pattern}\n")
            print("Created dangerous_patterns.txt with default patterns")
        except Exception as e:
            log.error(f"Failed to create dangerous_patterns.txt: {e}")
    
    # Try to read safe patterns from file
    try:
        with open("safe_patterns.txt", "r") as f:
            safe_patterns = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        # Default safe patterns if file not found
        safe_patterns = [
            # File listing and navigation
            r"\bls\s+",  # listing files
            r"\bdir\s+",  # Windows listing files
            r"Get-ChildItem\s+",  # PowerShell listing files (without dangerous parameters)
            r"\becho\s+",  # echo commands
            r"\bpwd\s+",  # print working directory
            r"\bcd\s+",  # change directory
            r"Set-Location\s+",  # PowerShell change directory
            r"Get-Location\b",  # PowerShell get location
            
            # System information
            r"\bwhoami\s*$",  # whoami
            r"\bdate\s*$",  # date
            r"\btime\s*$",  # time
            r"Get-Date\b",  # PowerShell date
            r"\bclear\s*$",  # clear screen
            r"\bcls\s*$",  # Windows clear screen
            r"Clear-Host\b",  # PowerShell clear screen
            r"\bhistory\s*$",  # command history
            r"Get-History\b",  # PowerShell history
            
            # Help and documentation
            r"\bhelp\s+",  # help commands
            r"\bman\s+",  # manual pages
            r"Get-Help\b",  # PowerShell help
            r"Get-Command\b",  # PowerShell command listing
            
            # File operations (read-only)
            r"\bfind\s+",  # find commands (generally safe)
            r"\bfindstr\s+",  # Windows find in strings
            r"\bgrep\s+",  # grep (unless on sensitive files)
            r"Select-String\b",  # PowerShell grep
            r"\bcat\s+",  # cat files (unless sensitive)
            r"\btype\s+",  # Windows type files
            r"Get-Content\b",  # PowerShell read files (unless sensitive)
            
            # Network diagnostics
            r"\bping\s+",  # ping commands
            r"Test-Connection\b",  # PowerShell ping
            r"Test-NetConnection\b",  # PowerShell network test
            r"\bnetstat\s+",  # network statistics
            r"Get-NetTCPConnection\b",  # PowerShell netstat
            r"\bipconfig\s*$",  # Windows IP configuration
            r"\bifconfig\s*$",  # IP configuration
            r"Get-NetIPAddress\b",  # PowerShell IP config
            r"Get-NetAdapter\b",  # PowerShell network adapters
            r"\bnslookup\s+",  # DNS lookup
            r"Resolve-DnsName\b",  # PowerShell DNS lookup
            r"\btracert\s+",  # trace route
            r"Test-NetConnection\s+.*\s+-TraceRoute",  # PowerShell trace route
            
            # Process information
            r"\bps\s+",  # process status
            r"\btasklist\s*$",  # Windows process list
            r"Get-Process\b",  # PowerShell process list
            r"\btop\s*$",  # top processes
            r"Get-Counter\b",  # PowerShell performance counters
            
            # Disk information
            r"\bdf\s*$",  # disk free space
            r"\bdu\s+",  # disk usage
            r"Get-PSDrive\b",  # PowerShell drives
            r"Get-Volume\b",  # PowerShell volumes
            r"\bfree\s*$",  # memory usage
            r"Get-ComputerInfo\b",  # PowerShell computer info
            
            # System information
            r"\buname\s+",  # system information
            r"\bsysteminfo\s*$",  # Windows system information
            r"Get-ComputerInfo\b",  # PowerShell system information
            r"\bver\s*$",  # Windows version
            r"$PSVersionTable\b",  # PowerShell version
            r"Get-Host\b",  # PowerShell host information
        ]
        # Create the file with default patterns for future use
        try:
            with open("safe_patterns.txt", "w") as f:
                f.write("# List of safe command patterns - one regex per line\n")
                f.write("# Lines starting with # are comments\n\n")
                for pattern in safe_patterns:
                    f.write(f"{pattern}\n")
            print("Created safe_patterns.txt with default patterns")
        except Exception as e:
            log.error(f"Failed to create safe_patterns.txt: {e}")

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
    """Interactive setup for API key and base URL"""
    print("\n=== OpenAI API Configuration ===")
    
    # Current API key
    current_key = ""
    config_file = os.path.expanduser(CACHE_FOLDER + "/openai")
    if os.path.exists(config_file):
        with open(config_file) as f:
            current_key = f.read().strip()
        print(f"Current API key: {current_key[:10]}...{current_key[-4:] if len(current_key) > 14 else current_key}")
    else:
        print("No API key configured")
    
    # Current base URL
    base_url_file = os.path.expanduser(CACHE_FOLDER + "/openai_base_url")
    current_base_url = ""
    if os.path.exists(base_url_file):
        with open(base_url_file) as f:
            current_base_url = f.read().strip()
        print(f"Current API base URL: {current_base_url if current_base_url else 'Default (OpenAI)'}")
    else:
        print("Current API base URL: Default (OpenAI)")
    
    # Current model
    current_model = get_model_name()
    print(f"Current model: {current_model}")
    
    # Current safety mode
    safety_mode = get_safety_mode()
    safety_mode_desc = "Always ask for confirmation" if safety_mode == 0 else "Auto-run safe commands"
    print(f"Current safety mode: {safety_mode_desc}")
    
    print("\nOptions:")
    print("1. Update API key")
    print("2. Update API base URL (for OpenAI-compatible APIs)")
    print("3. Update model name")
    print("4. Update safety mode")
    print("5. Reset to OpenAI defaults")
    print("6. Continue with current settings")
    
    choice = input("\nSelect option (1-6): ").strip()
    
    if choice == "1":
        new_key = input("Enter new API key: ").strip()
        if new_key:
            os.makedirs(os.path.dirname(config_file), exist_ok=True)
            with open(config_file, "w") as f:
                f.write(new_key)
            print("API key updated!")
        else:
            print("API key not changed")
    
    elif choice == "2":
        print("\nPopular OpenAI-compatible APIs:")
        print("- OpenAI: https://api.openai.com/v1 (default)")
        print("- Azure OpenAI: https://your-resource.openai.azure.com/")
        print("- LocalAI: http://localhost:8080/v1")
        print("- Ollama: http://localhost:11434/v1")
        print("- LM Studio: http://localhost:1234/v1")
        
        new_base_url = input("\nEnter API base URL (leave empty for OpenAI default): ").strip()
        os.makedirs(os.path.dirname(base_url_file), exist_ok=True)
        with open(base_url_file, "w") as f:
            f.write(new_base_url)
        
        if new_base_url:
            print(f"API base URL set to: {new_base_url}")
        else:
            print("API base URL reset to OpenAI default")
    
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
            model_file = os.path.expanduser(CACHE_FOLDER + "/openai_model")
            os.makedirs(os.path.dirname(model_file), exist_ok=True)
            with open(model_file, "w") as f:
                f.write(new_model)
            print(f"Model set to: {new_model}")
        else:
            print("Model not changed")
    
    elif choice == "4":
        print("\nSafety Modes:")
        print("0 - Always ask for confirmation before executing commands (default)")
        print("1 - Auto-run commands that appear safe, ask for confirmation on potentially dangerous commands")
        
        try:
            new_mode = int(input("\nEnter safety mode (0 or 1): ").strip())
            if new_mode in [0, 1]:
                safety_file = os.path.expanduser(CACHE_FOLDER + "/openai_safety_mode")
                os.makedirs(os.path.dirname(safety_file), exist_ok=True)
                with open(safety_file, "w") as f:
                    f.write(str(new_mode))
                
                mode_desc = "Always ask for confirmation" if new_mode == 0 else "Auto-run safe commands"
                print(f"Safety mode set to: {mode_desc}")
            else:
                print("Invalid mode. Safety mode not changed.")
        except ValueError:
            print("Invalid input. Safety mode not changed.")
    
    elif choice == "5":
        # Reset to defaults
        files_to_remove = [
            os.path.expanduser(CACHE_FOLDER + "/openai_base_url"),
            os.path.expanduser(CACHE_FOLDER + "/openai_model"),
            os.path.expanduser(CACHE_FOLDER + "/openai_safety_mode")
        ]
        for file_path in files_to_remove:
            if os.path.exists(file_path):
                os.remove(file_path)
        print("Reset to OpenAI defaults (gpt-4o-mini, always ask for confirmation). API key kept unchanged.")
    
    elif choice == "6":
        print("Continuing with current settings...")
    
    else:
        print("Invalid choice, continuing with current settings...")
    
    print("=" * 35)


def get_context_files():
    context_files = os.listdir(os.getcwd())
    context_prompt = ""
    # add the current folder to the prompt
    if len(context_files) > 0:
        context_prompt = (
            "The command is executed in folder %s contining the following list of files:\n"
            % (os.getcwd())
        )
        # add the files to the prompt
        context_prompt += "\n".join(context_files)
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

    model_name = get_model_name()
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": f"You can output only terminal commands! No info! No comments. No backticks. This system is running on {system_info}. If on Windows, use PowerShell or CMD commands, NOT Linux/Unix commands."},
            {"role": "user", "content": "Generate a single bash command to %s\n%s" % (prompt, context_prompt)},
        ],
        max_tokens=100,
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
    parser.add_argument("text", nargs="*", help="your query to the ai")

    args = parser.parse_args()

    # Handle configuration mode
    if args.config:
        setup_api_configuration()
        sys.exit(0)

    # Check if we have a query (only when not in chat mode)
    if not args.chat and not args.text:
        print("Please provide a command to execute or use --config to configure API settings.")
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
    cmd = get_cmd(client, prompt, context_prompt=context_prompt)

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
        for cmd in cmds:
            print("%d. \033[1;32m%s\033[0m" % (index, cmd))
            # Analyze alternative command safety
            alt_is_safe, alt_safety_reason = analyze_command_safety(cmd)
            if alt_is_safe:
                print(f"   Safety: \033[1;32mSafe\033[0m - {alt_safety_reason}")
            else:
                print(f"   Safety: \033[1;31mPotentially dangerous\033[0m - {alt_safety_reason}")
                
            if args.e:
                print_explaination(client, cmd)
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

    if not os.environ.get("NOHISTORY"):
        # retrieve the history file of the shell depending on the shell
        if PLATFORM == "Windows":
            if shell_type == "powershell":
                # PowerShell history
                history_file = os.path.expanduser("~/AppData/Roaming/Microsoft/Windows/PowerShell/PSReadLine/ConsoleHost_history.txt")
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

    # Execute the command in the current shell
    if PLATFORM == "Windows":
        if shell_type == "powershell":
            subprocess.call(["powershell", "-Command", cmd], shell=False)
        else:
            subprocess.call(cmd, shell=True)
    else:
        subprocess.call(cmd, shell=True, executable=shell)
