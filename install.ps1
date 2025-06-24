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

Write-Host "Installing TerminalAI for Windows..." -ForegroundColor Green

# Check if Python is installed
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+)\.(\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 7)) {
            Write-Host "Python 3.7 or higher is required. Current version: $pythonVersion" -ForegroundColor Red
            exit 1
        }
        Write-Host "Python version: $pythonVersion" -ForegroundColor Green
    } else {
        Write-Host "Python not found or version could not be determined" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Python is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python 3.7+ from https://python.org" -ForegroundColor Yellow
    exit 1
}

# Create virtual environment
$ENV_PATH = "$env:USERPROFILE\.virtualenvs\terminalai"
if (-not (Test-Path $ENV_PATH)) {
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv $ENV_PATH
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create virtual environment" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Virtual environment already exists" -ForegroundColor Green
}

# Activate virtual environment and install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
& "$ENV_PATH\Scripts\activate.ps1"
pip install --upgrade pip
pip install -r "$SCRIPT_DIR\requirements.txt"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install dependencies" -ForegroundColor Red
    exit 1
}

# Create batch file wrapper
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

Write-Host "Created ai.bat wrapper" -ForegroundColor Green

# Add to PATH
$currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($currentPath -notlike "*$SCRIPT_DIR*") {
    $newPath = "$currentPath;$SCRIPT_DIR"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-Host "Added $SCRIPT_DIR to user PATH" -ForegroundColor Green
} else {
    Write-Host "Path already contains script directory" -ForegroundColor Green
}

# Build executable if requested
if ($BuildExe) {
    Write-Host ""
    Write-Host "Building standalone executable..." -ForegroundColor Green

    # Check if PyInstaller is installed
    try {
        pyinstaller --version | Out-Null
        Write-Host "PyInstaller found" -ForegroundColor Green
    } catch {
        Write-Host "Installing PyInstaller..." -ForegroundColor Yellow
        pip install pyinstaller
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to install PyInstaller" -ForegroundColor Red
            exit 1
        }
    }

    # Clean build directory if requested
    if ($Clean) {
        Write-Host "Cleaning build directories..." -ForegroundColor Yellow
        if (Test-Path $BUILD_DIR) { Remove-Item -Recurse -Force $BUILD_DIR }
        if (Test-Path $DIST_DIR) { Remove-Item -Recurse -Force $DIST_DIR }
        if (Test-Path "$SCRIPT_DIR\ai.spec") { Remove-Item "$SCRIPT_DIR\ai.spec" }
    }

    # Create PyInstaller spec file
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

    $specFile = "$SCRIPT_DIR\ai.spec"
    $specContent | Out-File -FilePath $specFile -Encoding UTF8

    Write-Host "Created PyInstaller spec file" -ForegroundColor Green

    # Build the executable
    Write-Host "Building executable..." -ForegroundColor Yellow
    if ($OneFile) {
        pyinstaller --onefile --console ai.py
    } else {
        pyinstaller ai.spec
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }

    # Check if executable was created
    $exePath = "$DIST_DIR\ai.exe"
    if (Test-Path $exePath) {
        $fileSize = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
        Write-Host "Build successful!" -ForegroundColor Green
        Write-Host "Executable: $exePath" -ForegroundColor Cyan
        Write-Host "Size: $fileSize MB" -ForegroundColor Cyan
        
        # Test the executable
        Write-Host "Testing executable..." -ForegroundColor Yellow
        try {
            & $exePath "--help" | Out-Null
            Write-Host "Executable test passed!" -ForegroundColor Green
        } catch {
            Write-Host "Warning: Executable test failed" -ForegroundColor Yellow
        }
        
        # Create C:\TerminalAI directory if it doesn't exist
        if (-not (Test-Path $INSTALL_DIR)) {
            Write-Host "Creating $INSTALL_DIR directory..." -ForegroundColor Yellow
            New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
        } else {
            Write-Host "$INSTALL_DIR directory already exists" -ForegroundColor Green
        }
        
        # Copy executable to C:\TerminalAI
        Write-Host "Copying executable to $INSTALL_DIR..." -ForegroundColor Yellow
        Copy-Item $exePath "$INSTALL_DIR\ai.exe" -Force
        
        # Create batch wrapper in C:\TerminalAI
        $installBatchContent = @"
@echo off
:: TerminalAI Windows Executable
:: No Python installation required

"%~dp0ai.exe" %*
"@
        $installBatchContent | Out-File -FilePath "$INSTALL_DIR\ai.bat" -Encoding ASCII
        Write-Host "Created ai.bat wrapper in $INSTALL_DIR" -ForegroundColor Green
        
        # Add C:\TerminalAI to PATH if not already there
        if ($currentPath -notlike "*$INSTALL_DIR*") {
            $newPath = "$currentPath;$INSTALL_DIR"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
            Write-Host "Added $INSTALL_DIR to user PATH" -ForegroundColor Green
        } else {
            Write-Host "$INSTALL_DIR already in PATH" -ForegroundColor Green
        }
    } else {
        Write-Host "Build failed - executable not found!" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "You can now use 'ai' command from any directory" -ForegroundColor Green
Write-Host "Example: ai list all files in current directory" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: You'll be prompted for your OpenAI API key on first run" -ForegroundColor Yellow
Write-Host "Please restart your terminal or run: refreshenv" -ForegroundColor Yellow 