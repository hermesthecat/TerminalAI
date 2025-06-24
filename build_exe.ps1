# PowerShell script to build Windows executable for TerminalAI

param(
    [switch]$Help,
    [switch]$Debug,
    [switch]$OneFile = $true,
    [switch]$Clean
)

if ($Help) {
    Write-Host "TerminalAI Windows EXE Builder" -ForegroundColor Green
    Write-Host "Usage: .\build_exe.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help        Show this help message"
    Write-Host "  -Debug       Build with debug information (larger file)"
    Write-Host "  -OneFile     Build as single executable (default: true)"
    Write-Host "  -Clean       Clean build directory before building"
    Write-Host ""
    Write-Host "This script will:"
    Write-Host "  1. Check PyInstaller installation"
    Write-Host "  2. Create build configuration"
    Write-Host "  3. Build standalone executable"
    Write-Host "  4. Create distribution package"
    exit
}

# Get the directory of the current script
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BUILD_DIR = "$SCRIPT_DIR\build"
$DIST_DIR = "$SCRIPT_DIR\dist"

Write-Host "Building TerminalAI Windows Executable..." -ForegroundColor Green

# Check if virtual environment exists
$ENV_PATH = "$env:USERPROFILE\.virtualenvs\terminalai"
if (-not (Test-Path $ENV_PATH)) {
    Write-Host "Virtual environment not found. Please run install.ps1 first." -ForegroundColor Red
    exit 1
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& "$ENV_PATH\Scripts\activate.ps1"

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
    
    # Create distribution package
    Write-Host "Creating distribution package..." -ForegroundColor Yellow
    $distPackage = "$SCRIPT_DIR\terminalai-windows-portable.zip"
    
    # Create temp directory for package
    $tempDir = "$env:TEMP\terminalai-package"
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Copy files to package
    Copy-Item $exePath "$tempDir\ai.exe"
    Copy-Item "$SCRIPT_DIR\README.md" "$tempDir\"
    
    # Create simple batch wrapper for the executable
    $exeBatchContent = @"
@echo off
:: TerminalAI Portable Windows Executable
:: No Python installation required

"%~dp0ai.exe" %*
"@
    
    $exeBatchContent | Out-File -FilePath "$tempDir\ai.bat" -Encoding ASCII
    
    # Create usage instructions
    $usageContent = @"
# TerminalAI - Portable Windows Version

This is a standalone executable version of TerminalAI that doesn't require Python installation.

## Quick Start

1. Get your OpenAI API key from: https://platform.openai.com/api-keys
2. Run: ai.exe "list all files in current directory"
3. Enter your API key when prompted

## Usage

ai.exe <your command description>

Examples:
- ai.exe "find all Python files"
- ai.exe "show system information"
- ai.exe "list running services"

## Files

- ai.exe - Main executable (standalone, no Python required)
- ai.bat - Batch wrapper for easier command line usage
- README.md - Full documentation

## Adding to PATH

To use 'ai' command from anywhere:
1. Add this folder to your Windows PATH
2. Use either 'ai' (batch) or 'ai.exe' (direct executable)

Built with PyInstaller for Windows portability.
"@
    
    $usageContent | Out-File -FilePath "$tempDir\USAGE.txt" -Encoding UTF8
    
    # Create ZIP package
    if (Get-Command Compress-Archive -ErrorAction SilentlyContinue) {
        if (Test-Path $distPackage) { Remove-Item $distPackage }
        Compress-Archive -Path "$tempDir\*" -DestinationPath $distPackage
        Write-Host "Distribution package: $distPackage" -ForegroundColor Cyan
    } else {
        Write-Host "Warning: Compress-Archive not available, manual packaging required" -ForegroundColor Yellow
        Write-Host "Package files located at: $tempDir" -ForegroundColor Yellow
    }
    
    # Cleanup temp directory
    Remove-Item -Recurse -Force $tempDir
    
} else {
    Write-Host "Build failed - executable not found!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Build completed successfully!" -ForegroundColor Green
Write-Host "You can now distribute the executable without requiring Python installation." -ForegroundColor Green 