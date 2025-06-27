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
    echo "TerminalAI Linux/macOS Kurulum Betiği"
    echo "Kullanım: ./install.sh [seçenekler]"
    echo ""
    echo "Seçenekler:"
    echo "  -h, --help        Bu yardım menüsünü gösterir"
    echo "  --no-build-exe    Taşınabilir dosya oluşturmayı atlar"
    echo "  --debug           Hata ayıklama bilgileri içeren büyük dosya oluştur"
    echo "  --no-onefile      Dizin olarak değil tek dosya olarak oluştur"
    echo "  --clean           Derleme için derleme dizinini temizle"
    echo ""
    echo "Bu betik:"
    echo "  1. Python kurulumunu kontrol eder"
    echo "  2. Python sanal ortamını oluşturur"
    echo "  3. Bağımlılıkları yükler"
    echo "  4. PATH'e komut dizinini ekler"
    echo "  5. Taşınabilir dosya oluşturur"
    echo "  6. /opt/TerminalAI klasörünü oluşturur"
    echo "  7. Taşınabilir dosyayı /opt/TerminalAI'ye kopyalar"
    echo "  8. PATH'e /opt/TerminalAI ekler"
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

echo -e "${C_GREEN}TerminalAI Kurulumu Başlatılıyor...${C_NC}"
write_info "Mevcut kabuk: $CURRENT_SHELL"
write_info "Kurulum dizini: $SCRIPT_DIR"

# Check if Python is installed
write_step "Adım 1: Python Sürümü Kontrol Ediliyor"
if command -v python3 &>/dev/null; then
    PYTHON_CMD="python3"
elif command -v python &>/dev/null; then
    PYTHON_CMD="python"
else
    write_error "Python yüklü değil veya PATH içinde bulunamadı. Lütfen Python 3.7+ sürümünü yükleyin."
fi

# Check Python version
PYTHON_VERSION=$($PYTHON_CMD -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.minor)")

if [ $PYTHON_MAJOR -lt 3 ] || ([ $PYTHON_MAJOR -eq 3 ] && [ $PYTHON_MINOR -lt 7 ]); then
    write_error "Python 3.7 veya üstü gereklidir. Bulunan sürüm: $PYTHON_VERSION"
fi
write_success "Uyumlu Python sürümü bulundu: $PYTHON_VERSION"

# Create virtual environment
write_step "Adım 2: Python Sanal Ortamı Hazırlanıyor"
ENV_PATH="$HOME/.virtualenvs/terminalai"
if [ ! -d "$ENV_PATH" ]; then
    write_info "Sanal ortam oluşturuluyor: $ENV_PATH"
    $PYTHON_CMD -m venv "$ENV_PATH"
    if [ $? -ne 0 ]; then
        write_error "Sanal ortam oluşturulamadı."
    fi
    write_success "Sanal ortam başarıyla oluşturuldu."
else
    write_success "Sanal ortam zaten mevcut: $ENV_PATH"
fi

# Activate virtual environment and install dependencies
write_step "Adım 3: Gerekli Python Paketleri Yükleniyor"
write_info "Sanal ortam aktive ediliyor ve bağımlılıklar yükleniyor..."
source "$ENV_PATH/bin/activate"
pip install --upgrade pip > /dev/null
pip install -r "$SCRIPT_DIR/requirements.txt"
if [ $? -ne 0 ]; then
    write_error "Bağımlılıklar yüklenemedi."
fi
write_success "Tüm bağımlılıklar başarıyla yüklendi."

# Create shell wrapper
write_step "Adım 4: Komut Sarmalayıcısı (ai) Oluşturuluyor"
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
write_success "'ai' komut sarmalayıcısı oluşturuldu: $SCRIPT_DIR/ai"

# Add the script directory to the PATH
write_step "Adım 5: PATH Ortam Değişkeni Güncelleniyor"
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
        write_info "$SCRIPT_DIR dizini $SHELL_CONFIG_FILE dosyasına ekleniyor."
        if [ "$CURRENT_SHELL" = "fish" ]; then
            mkdir -p "$(dirname "$SHELL_CONFIG_FILE")"
            echo "set -g fish_user_paths $SCRIPT_DIR \$fish_user_paths" >> "$SHELL_CONFIG_FILE"
        else
            echo -e "\n# TerminalAI için PATH" >> "$SHELL_CONFIG_FILE"
            echo "export PATH=\$PATH:$SCRIPT_DIR" >> "$SHELL_CONFIG_FILE"
        fi
        write_success "PATH başarıyla güncellendi."
        write_info "Değişikliğin etkili olması için 'source $SHELL_CONFIG_FILE' komutunu çalıştırın veya terminali yeniden başlatın."
    else
        write_success "Dizin zaten PATH içinde mevcut."
    fi
else
    write_info "Bilinmeyen kabuk: $CURRENT_SHELL. Lütfen $SCRIPT_DIR dizinini manuel olarak PATH'e ekleyin."
fi

# Build executable if requested
if [ "$BUILD_EXE" = true ]; then
    write_step "Adım 6: Taşınabilir Dosya Oluşturuluyor (İsteğe Bağlı)"
    
    # Check if PyInstaller is installed
    write_info "PyInstaller kontrol ediliyor..."
    if ! pip show pyinstaller &>/dev/null; then
        write_info "PyInstaller yükleniyor..."
        pip install pyinstaller
        if [ $? -ne 0 ]; then
            write_error "PyInstaller yüklenemedi."
        fi
        write_success "PyInstaller başarıyla yüklendi."
    else
        write_success "PyInstaller zaten yüklü."
    fi
    
    # Clean build directory if requested
    if [ "$CLEAN" = true ]; then
        write_info "Derleme dizinleri temizleniyor..."
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
    
    write_success "PyInstaller spec dosyası oluşturuldu"
    
    # Build the executable
    write_info "Taşınabilir dosya oluşturuluyor... (Bu işlem biraz zaman alabilir)"
    if [ "$ONE_FILE" = true ]; then
        pyinstaller --onefile --console ai.py
    else
        pyinstaller ai.spec
    fi
    
    if [ $? -ne 0 ]; then
        write_error "Taşınabilir dosya oluşturma işlemi başarısız oldu!"
    fi
    
    # Check if executable was created
    EXE_PATH="$DIST_DIR/ai"
    if [ -f "$EXE_PATH" ]; then
        FILE_SIZE=$(du -h "$EXE_PATH" | cut -f1)
        write_success "Taşınabilir dosya başarıyla oluşturuldu: $EXE_PATH"
        write_info "Dosya boyutu: $FILE_SIZE"
        
        # Test the executable
        write_info "Taşınabilir dosya test ediliyor..."
        if "$EXE_PATH" --help &>/dev/null; then
            write_success "Taşınabilir dosya testi geçti!"
        else
            write_info "Uyarı: Taşınabilir dosya testi başarısız!"
        fi
        
        # Create installation directory
        write_info "'$INSTALL_DIR' dizini oluşturulacak ve dosya kopyalanacak. sudo yetkisi gerekebilir."
        if [ ! -d "$INSTALL_DIR" ]; then
            sudo mkdir -p "$INSTALL_DIR"
            write_success "Dizin oluşturuldu: $INSTALL_DIR"
        fi
        
        # Copy executable to installation directory
        write_info "'$EXE_PATH' dosyası $INSTALL_DIR dizinine kopyalanıyor..."
        sudo cp "$EXE_PATH" "$INSTALL_DIR/ai"
        sudo cp "$SCRIPT_DIR/dangerous_patterns.txt" "$INSTALL_DIR/dangerous_patterns.txt"
        sudo cp "$SCRIPT_DIR/safe_patterns.txt" "$INSTALL_DIR/safe_patterns.txt"
        if [ $? -ne 0 ]; then
            write_error "Taşınabilir dosya kopyalanamadı. sudo yetkisi gerekebilir."
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
        write_success "ai.sh wrapper oluşturuldu: $INSTALL_DIR"
        
        # Add installation directory to PATH
        SYSTEM_PATH_FILE="/etc/profile.d/terminalai.sh"
        if [ ! -f "$SYSTEM_PATH_FILE" ]; then
            write_info "Sistem geneli PATH için $SYSTEM_PATH_FILE oluşturuluyor..."
            echo "export PATH=\$PATH:$INSTALL_DIR" | sudo tee "$SYSTEM_PATH_FILE" > /dev/null
            write_success "Sistem geneli PATH ayarlandı."
            write_info "Değişikliğin etkili olması için lütfen sistemden çıkış yapıp tekrar giriş yapın."
        else
            write_success "Sistem geneli PATH zaten ayarlı."
        fi
    else
        write_error "Oluşturulan taşınabilir dosya bulunamadı: $EXE_PATH"
    fi
fi

echo -e "\n${C_GREEN}Kurulum Tamamlandı!${C_NC}"
echo "Kullanmaya başlamak için yeni bir terminal açın ve 'ai <sorunuz>' yazın."


