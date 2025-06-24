# TerminalAI
This is a simple bash script that uses the OpenAI API to generate commands based on the user input.

## New Version
- Updated to latest OpenAI API
- Now using GPT-4o-mini for extra cost efficiency
- Added Windows support with PowerShell and CMD compatibility

### Known Issues
- History file updates automatically, but the history of the session does not.

e.g., in zsh, you need to run `fc -R` to update the history file.

## Install

### Linux/macOS
    git clone https://github.com/hermesthecat/terminalai
    cd bash-ai
    chmod +x install.sh
    ./install.sh

### Windows
    git clone https://github.com/hermesthecat/terminalai
    cd bash-ai
    powershell -ExecutionPolicy Bypass -File install.ps1

Or using PowerShell directly:
    .\install.ps1

#### Windows Standalone Executable
For systems without Python, you can build a standalone executable:

    # Install first, then build executable
    .\install.ps1 -BuildExe

Or build separately:
    .\build_exe.ps1

This creates a portable `ai.exe` that works without Python installation.

First time you run ai, it will install dependencies in a virtual environment and it will ask for the key to the api. 

You can get the key from [here](https://platform.openai.com/api-keys)


## Usage
`ai <what you want to do>`

![Demo gif](https://i.postimg.cc/VNqZh0tV/demo.gif)

### Context
`ai` is aware of the distro used. It will use the correct package manager to install dependencies.

On Windows, it detects Windows version and uses appropriate Windows commands (cmd, PowerShell, Windows-specific tools).

`-c` option will add the content of the current directory to the context. This will generate a better result. But it will significantly increase the number of tokens used.

`-e` option will generate an explanation of the command. This will significantly increase the number of tokens used.


![Context Demo gif](https://i.postimg.cc/gjfFWs3K/context.gif)

### Windows-Specific Features
- Supports both CMD and PowerShell environments
- Automatically detects PowerShell and uses appropriate commands
- Uses Windows-specific system commands (tasklist, net, ipconfig, netsh, etc.)
- Maintains PowerShell command history
- Works with Windows firewall and network configuration commands
- **Standalone executable option**: Build `ai.exe` for distribution without Python dependency

#### Building Standalone Executable
The Windows version can be compiled into a standalone executable using PyInstaller:

```powershell
# Build with default settings (single file, optimized)
.\build_exe.ps1

# Build with debug information
.\build_exe.ps1 -Debug

# Clean build and rebuild
.\build_exe.ps1 -Clean

# Build during installation
.\install.ps1 -BuildExe
```

The executable build creates:
- `dist/ai.exe` - Standalone executable (~40-60MB)
- `terminalai-windows-portable.zip` - Distribution package with executable and documentation

**Benefits of standalone executable:**
- No Python installation required
- Single file distribution
- Faster startup (no virtual environment activation)
- Portable across Windows systems
- Ideal for corporate environments with restricted software installation

