# TerminalAI

This is a simple bash script that uses the OpenAI API to generate commands based on the user input.

## New Version (0.9.0)

- Updated to latest OpenAI API
- Now using GPT-4o-mini for extra cost efficiency
- Added Windows support with PowerShell and CMD compatibility
- **New:** Command safety analysis and auto-execution of safe commands
- **New:** Support for custom API providers (OpenAI, Azure, LocalAI, Ollama, etc.)
- **New:** Configurable model selection
- **New:** Customizable safety patterns via external files
- **New:** Centralized configuration via a single `config.ini` file.
- **New:** Auto-correct on failure: AI suggests a fix when a command fails.
- **New:** Multi-step command execution for complex tasks.
- **New:** Interactive command history (`ai --history`) for re-running previous commands.
- **New:** Smart Context Analysis (`-c` flag) that reads important project files.
- **New:** Self-updating mechanism (`ai --update`).

### Known Issues

- History file updates automatically, but the history of the session does not.

e.g., in zsh, you need to run `fc -R` to update the history file.

## Install

### Linux/macOS

    git clone https://github.com/hermesthecat/terminalai
    cd terminalai
    chmod +x install.sh
    ./install.sh

### Windows

    git clone https://github.com/hermesthecat/terminalai
    cd terminalai
    powershell -ExecutionPolicy Bypass -File install.ps1

Or using PowerShell directly:
    .\install.ps1

#### Windows Standalone Executable

For systems without Python, you can build a standalone executable during the installation process:

    # Install and build the executable at the same time
    .\install.ps1 -BuildExe

This creates a portable `ai.exe` in the `dist` folder that works without a Python installation.

First time you run ai, it will install dependencies in a virtual environment and it will ask for the key to the api.

You can get your API key from the [OpenAI API keys page](https://platform.openai.com/api-keys).

## Usage

`ai <what you want to do>`

### Configuration

You can configure API settings, model selection, and safety options via an interactive menu:

    ai --config

This opens an interactive menu with the following options:

1. Update API key
2. Update API base URL (for OpenAI-compatible APIs)
3. Update model name
4. Update safety mode
5. Update auto-correct on failure
6. Update multi-step commands
7. Reset to OpenAI defaults
8. Exit

### Self-Updating

You can easily update TerminalAI to the latest version directly from the command line. This only works if you have installed the program by cloning the git repository.

    ai --update

This command will:

1. Fetch the latest changes from the official GitHub repository.
2. Re-run the appropriate installation script (`install.sh` or `install.ps1`) to apply any changes and install new dependencies.

### Command Safety Analysis

TerminalAI now analyzes commands for safety before execution:

- **Safety Mode 0 (Default):** Always asks for confirmation before executing commands
- **Safety Mode 1:** Automatically executes safe commands, asks for confirmation on potentially dangerous ones

Each command is analyzed and marked as either:

- **Safe:** Basic system information, navigation, or read-only commands
- **Potentially Dangerous:** System modifications, privilege escalation, network changes, etc.

#### Customizable Safety Patterns

You can now customize the safety patterns used to analyze commands by editing two files:

- **dangerous_patterns.txt**: Contains regex patterns for potentially dangerous commands
- **safe_patterns.txt**: Contains regex patterns for commands that are considered safe

These files are created automatically with default patterns when the program runs for the first time. You can add, remove, or modify patterns to suit your specific needs.

Example of adding custom patterns:

    # In dangerous_patterns.txt
    # Add custom dangerous pattern
    custom-dangerous-command\s+  # My custom dangerous command

    # In safe_patterns.txt
    # Add custom safe pattern
    custom-safe-command\s+  # My custom safe command

Lines starting with `#` are treated as comments and ignored.

### Auto-correct on Failure

When a command fails (i.e., exits with a non-zero status code), TerminalAI can automatically attempt to fix it.

- **How it works:** If a command fails and produces an error message (`stderr`), TerminalAI sends the failed command and the error message back to the AI, asking for a corrected command.
- **Confirmation:** You will be shown the suggested fix and asked for confirmation before the new command is executed.
- **Configuration:** This feature is disabled by default. You can enable it via the `ai --config` menu.

### Interactive Command History

TerminalAI keeps a history of successfully executed commands. You can access and re-run these commands easily.

    ai --history

- **How it works:** This command displays a numbered list of your most recent successful commands.
- **Execution:** Simply enter the number of the command you wish to execute again and press Enter. You will be asked for confirmation before the command is run.
- **Benefit:** Quickly reuse complex commands without having to type them again or search through your shell's extensive history.

### Multi-Step Command Execution

For complex requests that require more than one command (e.g., "clone a repo, enter the directory, and install dependencies"), TerminalAI can generate a sequence of commands.

- **How it works:** When enabled, the AI can return a list of commands. The script will show you the entire sequence, with a safety analysis for each step.
- **Confirmation:** You will be asked to approve the entire sequence before execution begins. If you decline, no commands will be run.
- **Execution:** If you approve, the commands are executed one by one. If any command in the sequence fails, the execution stops immediately.
- **Configuration:** This feature is disabled by default. You can enable it via the `ai --config` menu.

### Custom API Providers

You can use TerminalAI with various OpenAI-compatible APIs:

- **OpenAI** (default)
- **Azure OpenAI**
- **LocalAI** (<http://localhost:8080/v1>)
- **Ollama** (<http://localhost:11434/v1>)
- **LM Studio** (<http://localhost:1234/v1>)
- Any other OpenAI-compatible API

### Model Selection

Choose from various models depending on your API provider:

- **OpenAI:** gpt-4o-mini (default), gpt-4o, gpt-4-turbo, gpt-3.5-turbo
- **LocalAI/Ollama:** llama3.2:3b, llama3.1:8b, codellama:7b, mistral:7b
- **Azure OpenAI:** Your deployment name

### Context

`ai` is aware of the distro used. It will use the correct package manager to install dependencies.

On Windows, it detects Windows version and uses appropriate Windows commands (cmd, PowerShell, Windows-specific-tools).

`-c` option will add the content of the current directory to the context. This will generate a better result. But it will significantly increase the number of tokens used. For example, if you are in a directory with a `docker-compose.yml` and ask `ai -c "restart the web server"`, TerminalAI will use the contents of `docker-compose.yml` to figure out that "web server" corresponds to the `nginx` service and generate the command `docker-compose restart nginx`.

### Smart Context Analysis (`-c` flag)

The `-c` flag makes TerminalAI project-aware. When used, it doesn't just list files; it intelligently reads the content of key project files to provide rich context to the AI.

- **How it works:** When you use `ai -c "your request"`, the script automatically detects and reads files like `docker-compose.yml`, `package.json`, `requirements.txt`, `Makefile`, etc., in your current directory.
- **Benefit:** This allows the AI to understand your project's structure, dependencies, and available scripts, resulting in highly accurate and context-specific commands. For example, asking to "run tests" in a Node.js project will correctly use the test script defined in your `package.json`.

`-e` option will generate an explanation of the command. This will significantly increase the number of tokens used.

### Windows-Specific Features

- Supports both CMD and PowerShell environments
- Automatically detects PowerShell and uses appropriate commands
- Uses Windows-specific system commands (tasklist, net, ipconfig, netsh, etc.)
- Maintains PowerShell command history
- Works with Windows firewall and network configuration commands
- **Standalone executable option**: Build `ai.exe` for distribution without Python dependency

#### Building Standalone Executable

The Windows version can be compiled into a standalone executable using PyInstaller. This is done via a command-line flag during the normal installation process.

    # Install and build with default settings (single file, optimized)
    .\install.ps1 -BuildExe

    # The installer also supports debug builds if needed
    # .\install.ps1 -BuildExe -Debug

The executable build creates:

- `dist/ai.exe` - Standalone executable (~40-60MB)
- `terminalai-windows-portable.zip` - Distribution package with executable and documentation

**Benefits of standalone executable:**

- No Python installation required
- Single file distribution
- Faster startup (no virtual environment activation)
- Portable across Windows systems
- Ideal for corporate environments with restricted software installation

### Configuration File

All TerminalAI settings are now stored in a single `config.ini` file. This file is located in the following directory depending on your operating system:

- **Linux/macOS:** `/opt/TerminalAI/`
- **Windows:** `C:/TerminalAI/`

The `config.ini` file will be created automatically the first time you run `ai` or use the `ai --config` command.
