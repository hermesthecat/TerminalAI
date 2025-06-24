#!/bin/bash

# Terminal AI installation script for Linux
# This script installs Terminal AI and optionally builds a standalone executable

# Default settings
BUILD_EXE=true
DEBUG=false
ONE_FILE=true
CLEAN=false
INSTALL_DIR="/opt/TerminalAI"

# Help function
show_help() {
    echo "TerminalAI Linux Installation Script"
    echo "Usage: ./install.sh [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  --no-build-exe    Skip building standalone executable"
    echo "  --debug           Build with debug information (larger file)"
    echo "  --no-onefile      Build as directory instead of single executable"
    echo "  --clean           Clean build directory before building"
    echo ""
    echo "This script will:"
    echo "  1. Check Python installation"
    echo "  2. Create a virtual environment"
    echo "  3. Install dependencies"
    echo "  4. Add script directory to PATH"
    echo "  5. Build standalone executable"
    echo "  6. Create /opt/TerminalAI folder"
    echo "  7. Copy executable to /opt/TerminalAI"
    echo "  8. Add /opt/TerminalAI to PATH"
    exit 0
}

# Parse arguments
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            ;;
        --no-build-exe)
            BUILD_EXE=false
            ;;
        --debug)
            DEBUG=true
            ;;
        --no-onefile)
            ONE_FILE=false
            ;;
        --clean)
            CLEAN=true
            ;;
    esac
done

# Get the directory of the current script
SCRIPT_DIR=$(cd $(dirname $0); pwd)
BUILD_DIR="$SCRIPT_DIR/build"
DIST_DIR="$SCRIPT_DIR/dist"

# Get the current shell name
CURRENT_SHELL=$(basename "$SHELL")

echo -e "\e[32mInstalling TerminalAI for Linux...\e[0m"
echo "Current shell: $CURRENT_SHELL"

# Check if Python is installed
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    echo -e "\e[31mPython is not installed or not in PATH\e[0m"
    echo -e "\e[33mPlease install Python 3.7+ from your package manager\e[0m"
    exit 1
fi

# Check Python version
PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}')")
PYTHON_MAJOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.minor)")

if [ $PYTHON_MAJOR -lt 3 ] || ([ $PYTHON_MAJOR -eq 3 ] && [ $PYTHON_MINOR -lt 7 ]); then
    echo -e "\e[31mPython 3.7 or higher is required. Current version: $PYTHON_VERSION\e[0m"
    exit 1
fi

echo -e "\e[32mPython version: $PYTHON_VERSION\e[0m"

# Create virtual environment
ENV_PATH="$HOME/.virtualenvs/terminalai"
if [ ! -d "$ENV_PATH" ]; then
    echo -e "\e[33mCreating virtual environment...\e[0m"
    $PYTHON_CMD -m venv "$ENV_PATH"
    if [ $? -ne 0 ]; then
        echo -e "\e[31mFailed to create virtual environment\e[0m"
        exit 1
    fi
else
    echo -e "\e[32mVirtual environment already exists\e[0m"
fi

# Activate virtual environment and install dependencies
echo -e "\e[33mInstalling dependencies...\e[0m"
source "$ENV_PATH/bin/activate"
pip install --upgrade pip
pip install -r "$SCRIPT_DIR/requirements.txt"

if [ $? -ne 0 ]; then
    echo -e "\e[31mFailed to install dependencies\e[0m"
    exit 1
fi

# Create shell wrapper
WRAPPER_CONTENT="#!/bin/bash
ENV_PATH=\"$HOME/.virtualenvs/terminalai\"
COMMAND_PATH=\"$SCRIPT_DIR/ai.py\"

if [ ! -d \"\$ENV_PATH\" ]; then
    echo \"Virtual environment not found. Please run install.sh first.\"
    exit 1
fi

source \"\$ENV_PATH/bin/activate\"
python \"\$COMMAND_PATH\" \"\$@\"
"

echo "$WRAPPER_CONTENT" > "$SCRIPT_DIR/ai"
chmod +x "$SCRIPT_DIR/ai"
echo -e "\e[32mCreated ai wrapper script\e[0m"

# Add the script directory to the PATH
if [ "$CURRENT_SHELL" = "bash" ]; then
    if ! grep -q "export PATH=\$PATH:$SCRIPT_DIR" ~/.bashrc; then
        echo "export PATH=\$PATH:$SCRIPT_DIR" >> ~/.bashrc
        echo -e "\e[32mAdded $SCRIPT_DIR to PATH in .bashrc\e[0m"
    else
        echo -e "\e[32mPath already contains script directory\e[0m"
    fi
elif [ "$CURRENT_SHELL" = "zsh" ]; then
    if ! grep -q "export PATH=\$PATH:$SCRIPT_DIR" ~/.zshrc; then
        echo "export PATH=\$PATH:$SCRIPT_DIR" >> ~/.zshrc
        echo -e "\e[32mAdded $SCRIPT_DIR to PATH in .zshrc\e[0m"
    else
        echo -e "\e[32mPath already contains script directory\e[0m"
    fi
elif [ "$CURRENT_SHELL" = "fish" ]; then
    if ! grep -q "set -g fish_user_paths $SCRIPT_DIR" ~/.config/fish/config.fish 2>/dev/null; then
        mkdir -p ~/.config/fish
        echo "set -g fish_user_paths $SCRIPT_DIR \$fish_user_paths" >> ~/.config/fish/config.fish
        echo -e "\e[32mAdded $SCRIPT_DIR to PATH in fish config\e[0m"
    else
        echo -e "\e[32mPath already contains script directory\e[0m"
    fi
else
    echo -e "\e[33mUnknown shell: $CURRENT_SHELL\e[0m"
    echo -e "\e[33mPlease manually add $SCRIPT_DIR to your PATH\e[0m"
fi

# Build executable if requested
if [ "$BUILD_EXE" = true ]; then
    echo ""
    echo -e "\e[32mBuilding standalone executable...\e[0m"
    
    # Check if PyInstaller is installed
    if ! pip show pyinstaller &>/dev/null; then
        echo -e "\e[33mInstalling PyInstaller...\e[0m"
        pip install pyinstaller
        if [ $? -ne 0 ]; then
            echo -e "\e[31mFailed to install PyInstaller\e[0m"
            exit 1
        fi
    else
        echo -e "\e[32mPyInstaller found\e[0m"
    fi
    
    # Clean build directory if requested
    if [ "$CLEAN" = true ]; then
        echo -e "\e[33mCleaning build directories...\e[0m"
        rm -rf "$BUILD_DIR" 2>/dev/null
        rm -rf "$DIST_DIR" 2>/dev/null
        rm -f "$SCRIPT_DIR/ai.spec" 2>/dev/null
    fi
    
    # Create PyInstaller spec file
    DEBUG_VALUE=$([ "$DEBUG" = true ] && echo "True" || echo "False")
    
    cat > "$SCRIPT_DIR/ai.spec" << EOF
# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['ai.py'],
    pathex=['$SCRIPT_DIR'],
    binaries=[],
    datas=[],
    hiddenimports=[
        'distro',
        'openai',
        'platform',
        'subprocess',
        'pickle',
        'argparse',
        'logging',
        'signal',
        'time',
        'collections',
        're',
        'os',
        'sys'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='ai',
    debug=$DEBUG_VALUE,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
EOF
    
    echo -e "\e[32mCreated PyInstaller spec file\e[0m"
    
    # Build the executable
    echo -e "\e[33mBuilding executable...\e[0m"
    if [ "$ONE_FILE" = true ]; then
        pyinstaller --onefile --console ai.py
    else
        pyinstaller ai.spec
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "\e[31mBuild failed!\e[0m"
        exit 1
    fi
    
    # Check if executable was created
    EXE_PATH="$DIST_DIR/ai"
    if [ -f "$EXE_PATH" ]; then
        FILE_SIZE=$(du -h "$EXE_PATH" | cut -f1)
        echo -e "\e[32mBuild successful!\e[0m"
        echo -e "\e[36mExecutable: $EXE_PATH\e[0m"
        echo -e "\e[36mSize: $FILE_SIZE\e[0m"
        
        # Test the executable
        echo -e "\e[33mTesting executable...\e[0m"
        if "$EXE_PATH" --help &>/dev/null; then
            echo -e "\e[32mExecutable test passed!\e[0m"
        else
            echo -e "\e[33mWarning: Executable test failed\e[0m"
        fi
        
        # Create installation directory
        if [ ! -d "$INSTALL_DIR" ]; then
            echo -e "\e[33mCreating $INSTALL_DIR directory...\e[0m"
            sudo mkdir -p "$INSTALL_DIR"
            if [ $? -ne 0 ]; then
                echo -e "\e[31mFailed to create installation directory. Try running with sudo.\e[0m"
                exit 1
            fi
        else
            echo -e "\e[32m$INSTALL_DIR directory already exists\e[0m"
        fi
        
        # Copy executable to installation directory
        echo -e "\e[33mCopying executable to $INSTALL_DIR...\e[0m"
        sudo cp "$EXE_PATH" "$INSTALL_DIR/ai"
        if [ $? -ne 0 ]; then
            echo -e "\e[31mFailed to copy executable. Try running with sudo.\e[0m"
            exit 1
        fi
        
        # Create wrapper script in installation directory
        INSTALL_WRAPPER="#!/bin/bash
# TerminalAI Linux Executable
# No Python installation required

\$(dirname \"\$0\")/ai \"\$@\"
"
        echo "$INSTALL_WRAPPER" | sudo tee "$INSTALL_DIR/ai.sh" > /dev/null
        sudo chmod +x "$INSTALL_DIR/ai.sh"
        sudo chmod +x "$INSTALL_DIR/ai"
        echo -e "\e[32mCreated ai.sh wrapper in $INSTALL_DIR\e[0m"
        
        # Add installation directory to PATH
        if [ "$CURRENT_SHELL" = "bash" ]; then
            if ! grep -q "export PATH=\$PATH:$INSTALL_DIR" ~/.bashrc; then
                echo "export PATH=\$PATH:$INSTALL_DIR" >> ~/.bashrc
                echo -e "\e[32mAdded $INSTALL_DIR to PATH in .bashrc\e[0m"
            else
                echo -e "\e[32m$INSTALL_DIR already in PATH\e[0m"
            fi
        elif [ "$CURRENT_SHELL" = "zsh" ]; then
            if ! grep -q "export PATH=\$PATH:$INSTALL_DIR" ~/.zshrc; then
                echo "export PATH=\$PATH:$INSTALL_DIR" >> ~/.zshrc
                echo -e "\e[32mAdded $INSTALL_DIR to PATH in .zshrc\e[0m"
            else
                echo -e "\e[32m$INSTALL_DIR already in PATH\e[0m"
            fi
        elif [ "$CURRENT_SHELL" = "fish" ]; then
            if ! grep -q "set -g fish_user_paths $INSTALL_DIR" ~/.config/fish/config.fish 2>/dev/null; then
                mkdir -p ~/.config/fish
                echo "set -g fish_user_paths $INSTALL_DIR \$fish_user_paths" >> ~/.config/fish/config.fish
                echo -e "\e[32mAdded $INSTALL_DIR to PATH in fish config\e[0m"
            else
                echo -e "\e[32m$INSTALL_DIR already in PATH\e[0m"
            fi
        else
            echo -e "\e[33mUnknown shell: $CURRENT_SHELL\e[0m"
            echo -e "\e[33mPlease manually add $INSTALL_DIR to your PATH\e[0m"
        fi
    else
        echo -e "\e[31mBuild failed - executable not found!\e[0m"
        exit 1
    fi
fi

echo ""
echo -e "\e[32mInstallation completed successfully!\e[0m"
echo -e "\e[32mYou can now use 'ai' command from any directory\e[0m"
echo -e "\e[36mExample: ai list all files in current directory\e[0m"
echo ""
echo -e "\e[33mNote: You'll be prompted for your OpenAI API key on first run\e[0m"
echo -e "\e[33mPlease restart your terminal or run: source ~/.bashrc (or your shell's equivalent)\e[0m"


