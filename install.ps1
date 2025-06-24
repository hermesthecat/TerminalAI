# PowerShell installation script for TerminalAI on Windows

param(
    [switch]$Help,
    [switch]$BuildExe
)

if ($Help) {
    Write-Host "TerminalAI Windows Installation Script"
    Write-Host "Usage: .\install.ps1 [options]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Help        Show this help message"
    Write-Host "  -BuildExe    Also build standalone executable after installation"
    Write-Host ""
    Write-Host "This script will:"
    Write-Host "  1. Check Python installation"
    Write-Host "  2. Create a virtual environment"
    Write-Host "  3. Install dependencies"
    Write-Host "  4. Add ai.bat to PATH"
    Write-Host "  5. Optionally build standalone EXE"
    exit
}

# Get the directory of the current script
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

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
    Write-Host "Please restart your terminal or run: refreshenv" -ForegroundColor Yellow
} else {
    Write-Host "Path already contains script directory" -ForegroundColor Green
}

# Build executable if requested
if ($BuildExe) {
    Write-Host ""
    Write-Host "Building standalone executable..." -ForegroundColor Yellow
    
    if (Test-Path "$SCRIPT_DIR\build_exe.ps1") {
        & "$SCRIPT_DIR\build_exe.ps1"
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "Executable build completed!" -ForegroundColor Green
            Write-Host "Portable version available in dist/ folder" -ForegroundColor Cyan
        } else {
            Write-Host "Executable build failed, but installation was successful" -ForegroundColor Yellow
        }
    } else {
        Write-Host "build_exe.ps1 not found, skipping executable build" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "You can now use 'ai' command from any directory" -ForegroundColor Green
Write-Host "Example: ai list all files in current directory" -ForegroundColor Cyan
Write-Host ""

if (-not $BuildExe) {
    Write-Host "To build a standalone executable (no Python required):" -ForegroundColor Yellow
    Write-Host "  .\build_exe.ps1" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "Note: You'll be prompted for your OpenAI API key on first run" -ForegroundColor Yellow 