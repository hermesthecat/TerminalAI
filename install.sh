#!/bin/bash

# Terminal AI installation script for Linux
# This script installs Terminal AI and optionally builds a standalone executable

# --- Ayarlar ---
BUILD_EXE=true
DEBUG=false
ONE_FILE=true
CLEAN=false
INSTALL_DIR="/opt/TerminalAI"

# --- Renkler ve Yardımcı Fonksiyonlar ---
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_RED='\033[0;31m'
C_NC='\033[0m' # No Color

write_step() {
    echo -e "\n${C_YELLOW}=== $1 ===${C_NC}"
}

write_success() {
    echo -e "${C_GREEN}[SUCCESS] $1${C_NC}"
}

write_info() {
    echo -e "${C_CYAN}[INFO] $1${C_NC}"
}

write_error() {
    echo -e "${C_RED}[ERROR] $1${C_NC}"
    exit 1
}

# --- Yardım Menüsü ---
show_help() {
    echo "TerminalAI Linux/macOS Installation Script"
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
    echo "  2. Create a Python virtual environment"
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

echo -e "${C_GREEN}Starting TerminalAI Installation...${C_NC}"
write_info "Current shell: $CURRENT_SHELL"
write_info "Installation directory: $SCRIPT_DIR"

# Check if Python is installed
write_step "Step 1: Checking Python Version"
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    write_error "Python is not installed or not in PATH. Please install Python 3.7+."
fi

# Check Python version
PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.minor)")

if [ $PYTHON_MAJOR -lt 3 ] || ([ $PYTHON_MAJOR -eq 3 ] && [ $PYTHON_MINOR -lt 7 ]); then
    write_error "Python 3.7 or higher is required. Found version: $PYTHON_VERSION"
fi
write_success "Compatible Python version found: $PYTHON_VERSION"

# Create virtual environment
write_step "Step 2: Preparing Python Virtual Environment"
ENV_PATH="$HOME/.virtualenvs/terminalai"
if [ ! -d "$ENV_PATH" ]; then
    write_info "Creating virtual environment: $ENV_PATH"
    $PYTHON_CMD -m venv "$ENV_PATH"
    if [ $? -ne 0 ]; then
        write_error "Failed to create virtual environment."
    fi
    write_success "Virtual environment created successfully."
else
    write_success "Virtual environment already exists: $ENV_PATH"
fi

# Activate virtual environment and install dependencies
write_step "Step 3: Installing Required Python Packages"
write_info "Activating virtual environment and installing dependencies..."
source "$ENV_PATH/bin/activate"
pip install --upgrade pip > /dev/null
pip install -r "$SCRIPT_DIR/requirements.txt"
if [ $? -ne 0 ]; then
    write_error "Failed to install dependencies."
fi
write_success "All dependencies installed successfully."

# Create shell wrapper
write_step "Step 4: Creating Command Wrapper (ai)"
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
write_success "'ai' command wrapper created: $SCRIPT_DIR/ai"

# Add the script directory to the PATH
write_step "Step 5: Updating PATH Environment Variable"
SHELL_CONFIG_FILE=""
if [ "$CURRENT_SHELL" = "bash" ]; then
    SHELL_CONFIG_FILE="$HOME/.bashrc"
elif [ "$CURRENT_SHELL" = "zsh" ]; then
    SHELL_CONFIG_FILE="$HOME/.zshrc"
elif [ "$CURRENT_SHELL" = "fish" ]; then
    SHELL_CONFIG_FILE="$HOME/.config/fish/config.fish"
fi

if [ -n "$SHELL_CONFIG_FILE" ]; then
    if ! grep -q "export PATH=\$PATH:$SCRIPT_DIR" "$SHELL_CONFIG_FILE" 2>/dev/null; then
        write_info "Adding $SCRIPT_DIR to $SHELL_CONFIG_FILE."
        if [ "$CURRENT_SHELL" = "fish" ]; then
            mkdir -p "$(dirname "$SHELL_CONFIG_FILE")"
            echo "set -g fish_user_paths $SCRIPT_DIR \$fish_user_paths" >> "$SHELL_CONFIG_FILE"
        else
            echo -e "\n# Path for TerminalAI" >> "$SHELL_CONFIG_FILE"
            echo "export PATH=\$PATH:$SCRIPT_DIR" >> "$SHELL_CONFIG_FILE"
        fi
        write_success "PATH updated successfully."
        write_info "For the change to take effect, run 'source $SHELL_CONFIG_FILE' or restart your terminal."
    else
        write_success "Directory already in PATH."
    fi
else
    write_info "Unknown shell: $CURRENT_SHELL. Please add $SCRIPT_DIR to your PATH manually."
fi

# Build executable if requested
if [ "$BUILD_EXE" = true ]; then
    write_step "Step 6: Building Standalone Executable (Optional)"
    
    # Check if PyInstaller is installed
    write_info "Checking for PyInstaller..."
    if ! pip show pyinstaller &>/dev/null; then
        write_info "Installing PyInstaller..."
        pip install pyinstaller
        if [ $? -ne 0 ]; then
            write_error "Failed to install PyInstaller."
        fi
        write_success "PyInstaller installed successfully."
    else
        write_success "PyInstaller is already installed."
    fi
    
    # Clean build directory if requested
    if [ "$CLEAN" = true ]; then
        write_info "Cleaning build directories..."
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
    
    write_success "PyInstaller spec file created"
    
    # Build the executable
    write_info "Building executable... (This may take a while)"
    if [ "$ONE_FILE" = true ]; then
        pyinstaller --onefile --console ai.py
    else
        pyinstaller ai.spec
    fi
    
    if [ $? -ne 0 ]; then
        write_error "Executable build failed!"
    fi
    
    # Check if executable was created
    EXE_PATH="$DIST_DIR/ai"
    if [ -f "$EXE_PATH" ]; then
        FILE_SIZE=$(du -h "$EXE_PATH" | cut -f1)
        write_success "Executable built successfully: $EXE_PATH"
        write_info "File size: $FILE_SIZE"
        
        # Test the executable
        write_info "Testing the executable..."
        if "$EXE_PATH" --help &>/dev/null; then
            write_success "Executable test passed!"
        else
            write_info "Warning: Executable test failed!"
        fi
        
        # Create installation directory
        write_info "'$INSTALL_DIR' will be created and the executable will be copied. This may require sudo privileges."
        if [ ! -d "$INSTALL_DIR" ]; then
            sudo mkdir -p "$INSTALL_DIR"
            write_success "Directory created: $INSTALL_DIR"
        fi
        
        # Copy executable to installation directory
        write_info "Copying '$EXE_PATH' to $INSTALL_DIR..."
        sudo cp "$EXE_PATH" "$INSTALL_DIR/ai"
        sudo cp "$SCRIPT_DIR/dangerous_patterns.txt" "$INSTALL_DIR/"
        sudo cp "$SCRIPT_DIR/safe_patterns.txt" "$INSTALL_DIR/"
        if [ $? -ne 0 ]; then
            write_error "Failed to copy executable. This may require sudo privileges."
        fi
        write_success "Required files copied to $INSTALL_DIR."
        
        # Create wrapper script in installation directory
        INSTALL_WRAPPER="#!/bin/bash
# TerminalAI Linux Executable
# No Python installation required

\$(dirname \"\$0\")/ai \"\$@\"
"
        echo "$INSTALL_WRAPPER" | sudo tee "$INSTALL_DIR/ai.sh" > /dev/null
        sudo chmod +x "$INSTALL_DIR/ai.sh"
        sudo chmod +x "$INSTALL_DIR/ai"
        write_success "ai.sh wrapper created: $INSTALL_DIR"
        
        # Add installation directory to PATH
        SYSTEM_PATH_FILE="/etc/profile.d/terminalai.sh"
        if [ ! -f "$SYSTEM_PATH_FILE" ]; then
            write_info "Creating system-wide PATH at $SYSTEM_PATH_FILE..."
            echo "export PATH=\$PATH:$INSTALL_DIR" | sudo tee "$SYSTEM_PATH_FILE" > /dev/null
            write_success "System-wide PATH has been set."
            write_info "Please log out and log back in for the changes to take effect."
        else
            write_success "System-wide PATH is already set."
        fi
    else
        write_error "Built executable not found: $EXE_PATH"
    fi
fi

echo -e "\n${C_GREEN}Installation Complete!${C_NC}"
echo "To get started, open a new terminal and type 'ai <your query>'."


