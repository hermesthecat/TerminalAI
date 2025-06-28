# PowerShell installation script for TerminalAI on Windows

param(
    [switch]$Help,
    [switch]$BuildExe = $true,
    [switch]$Debug,
    [switch]$OneFile = $true,
    [switch]$Clean
)

if ($Help) {
    Write-Host "TerminalAI Windows Installation Script"
    Write-Host "Usage: .\install.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help        Show this help message"
    Write-Host "  -BuildExe    Also build standalone executable after installation (default: true)"
    Write-Host "  -Debug       Build with debug information (larger file)"
    Write-Host "  -OneFile     Build as single executable (default: true)"
    Write-Host "  -Clean       Clean build directory before building"
    Write-Host ""
    Write-Host "This script will:"
    Write-Host "  1. Check Python installation"
    Write-Host "  2. Create a virtual environment"
    Write-Host "  3. Install dependencies"
    Write-Host "  4. Add ai.bat to PATH"
    Write-Host "  5. Build standalone EXE"
    Write-Host "  6. Create C:\TerminalAI folder"
    Write-Host "  7. Copy executable to C:\TerminalAI"
    Write-Host "  8. Add C:\TerminalAI to PATH"
    exit
}

# Get the directory of the current script
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$INSTALL_DIR = "C:\TerminalAI"
$BUILD_DIR = "$SCRIPT_DIR\build"
$DIST_DIR = "$SCRIPT_DIR\dist"

# Helper function for consistent output
function Write-Step {
    param($Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Yellow
}

function Write-Success {
    param($Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Info {
    param($Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Error {
    param($Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

Write-Host "Starting TerminalAI Installation..." -ForegroundColor Green

# 1. Python kontrolü
Write-Step "Step 1: Checking Python Version"
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+)\.(\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 7)) {
            Write-Error "Python 3.7 or higher is required. Current version: $pythonVersion"
        }
        Write-Success "Compatible Python version found: $pythonVersion"
    } else {
        Write-Error "Python not found or version could not be determined."
    }
} catch {
    Write-Host "Python is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Python 3.7+ from https://python.org" -ForegroundColor Yellow
    exit 1
}

# 2. Sanal ortam oluşturma
Write-Step "Step 2: Preparing Python Virtual Environment"
$ENV_PATH = "$env:USERPROFILE\.virtualenvs\terminalai"
if (-not (Test-Path $ENV_PATH)) {
    Write-Info "Creating virtual environment: $ENV_PATH"
    python -m venv $ENV_PATH
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to create virtual environment."
    }
    Write-Success "Virtual environment created successfully."
} else {
    Write-Success "Virtual environment already exists: $ENV_PATH"
}

# 3. Bağımlılıkları yükleme
Write-Step "Step 3: Installing Required Python Packages"
Write-Info "Activating virtual environment and installing dependencies..."
& "$ENV_PATH\Scripts\activate.ps1"
pip install --upgrade pip | Out-Null
pip install -r "$SCRIPT_DIR\requirements.txt"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install dependencies."
}
Write-Success "All dependencies installed successfully."

# 4. ai.bat sarmalayıcı (wrapper) oluşturma
Write-Step "Step 4: Creating Command Wrapper (ai.bat)"
$batchContent = @"
@echo off
set ENV_PATH=%USERPROFILE%\.virtualenvs\terminalai
set COMMAND_PATH=$SCRIPT_DIR\ai.py

if not exist "%ENV_PATH%" (
    echo Virtual environment not found. Please run install.ps1 first.
    exit /b 1
)

call "%ENV_PATH%\Scripts\activate.bat"
python "%COMMAND_PATH%" %*
"@

$batchFile = "$SCRIPT_DIR\ai.bat"
$batchContent | Out-File -FilePath $batchFile -Encoding ASCII
Write-Success "ai.bat file created: $batchFile"

# 5. PATH ortam değişkenine ekleme
Write-Step "Step 5: Updating PATH Environment Variable"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($currentPath -notlike "*$SCRIPT_DIR*") {
    $newPath = "$currentPath;$SCRIPT_DIR"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-Success "Added to user PATH: $SCRIPT_DIR"
    Write-Info "You may need to restart your terminal for the changes to take effect."
} else {
    Write-Success "Directory already in PATH: $SCRIPT_DIR"
}

# Build executable if requested
if ($BuildExe) {
    Write-Step "Step 6: Building Standalone EXE (Optional)"

    # PyInstaller kontrolü
    Write-Info "Checking for PyInstaller..."
    try {
        pyinstaller --version | Out-Null
        Write-Success "PyInstaller is already installed."
    } catch {
        Write-Info "Installing PyInstaller..."
        pip install pyinstaller
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install PyInstaller."
        }
        Write-Success "PyInstaller installed successfully."
    }

    # Temizlik
    if ($Clean) {
        Write-Info "Cleaning old build files..."
        if (Test-Path $BUILD_DIR) { Remove-Item -Recurse -Force $BUILD_DIR; Write-Info "Deleted: $BUILD_DIR" }
        if (Test-Path $DIST_DIR) { Remove-Item -Recurse -Force $DIST_DIR; Write-Info "Deleted: $DIST_DIR" }
        if (Test-Path "$SCRIPT_DIR\ai.spec") { Remove-Item "$SCRIPT_DIR\ai.spec"; Write-Info "Deleted: ai.spec" }
        Write-Success "Cleaning complete."
    }

    # PyInstaller spec dosyası
    $specFile = "$SCRIPT_DIR\ai.spec"
    if (-not (Test-Path $specFile)) {
        $specContent = @"
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
    debug=$($Debug.ToString().ToLower()),
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
"@
        # Bu sadece bir örnek, tam spec içeriği betikte zaten var. Gerçek kodda bunu değiştirmeyeceğim.
    }
    
    # Derleme
    Write-Info "Building EXE file... (This may take a while)"
    if ($OneFile) {
        pyinstaller --onefile --console ai.py
    } else {
        pyinstaller ai.spec
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "EXE build process failed!"
    }

    # Sonuç
    $exePath = "$DIST_DIR\ai.exe"
    if (Test-Path $exePath) {
        $fileSize = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
        Write-Success "EXE built successfully!"
        Write-Info "File: $exePath"
        Write-Info "Size: $fileSize MB"
        
        # Test
        Write-Info "Testing the created EXE..."
        try {
            & $exePath "--help" | Out-Null
            Write-Success "EXE test successful."
        } catch {
            Write-Host "[WARNING] EXE test failed." -ForegroundColor Yellow
        }
        
        # C:\TerminalAI dizinine kopyalama
        Write-Step "Step 7: Copying EXE for System-Wide Use"
        if (-not (Test-Path $INSTALL_DIR)) {
            Write-Info "Creating directory: $INSTALL_DIR"
            New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
            Write-Success "Directory created successfully."
        }
        
        Write-Info "Copying ai.exe to $INSTALL_DIR..."
        Copy-Item -Path $exePath -Destination $INSTALL_DIR -Force
        Copy-Item "$SCRIPT_DIR\dangerous_patterns.txt" "$INSTALL_DIR\dangerous_patterns.txt" -Force
        Copy-Item "$SCRIPT_DIR\safe_patterns.txt" "$INSTALL_DIR\safe_patterns.txt" -Force
        Write-Success "Copying complete."

        # C:\TerminalAI'ı PATH'e ekleme
        Write-Info "Updating system PATH variable..."
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
        if ($machinePath -notlike "*$INSTALL_DIR*") {
            $newMachinePath = "$machinePath;$INSTALL_DIR"
            # Bu komut yönetici izni gerektirir.
            try {
                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment' -Name 'Path' -Value $newMachinePath
                Write-Success "Added to system PATH: $INSTALL_DIR"
                Write-Info "You may need to restart your terminal for the changes to take effect."
            } catch {
                Write-Host "[WARNING] Could not update system PATH. Please run PowerShell as Administrator or add the directory manually: $INSTALL_DIR" -ForegroundColor Yellow
            }
        } else {
            Write-Success "Directory already in system PATH: $INSTALL_DIR"
        }
    } else {
        Write-Error "Created EXE file not found: $exePath"
    }
}

Write-Host "`nInstallation Complete!" -ForegroundColor Green
Write-Host "To get started, open a new terminal and type 'ai <your query>'."

Write-Host ""
Write-Host "Note: You'll be prompted for your OpenAI API key on first run" -ForegroundColor Yellow
Write-Host "Please restart your terminal or run: refreshenv" -ForegroundColor Yellow 