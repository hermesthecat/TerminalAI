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

Write-Host "TerminalAI Kurulumu Başlatılıyor..." -ForegroundColor Green

# 1. Python kontrolü
Write-Step "Adım 1: Python Sürümü Kontrol Ediliyor"
try {
    $pythonVersion = python --version 2>&1
    if ($pythonVersion -match "Python (\d+)\.(\d+)\.(\d+)") {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 7)) {
            Write-Error "Python 3.7 veya üstü gereklidir. Mevcut sürüm: $pythonVersion"
        }
        Write-Success "Uyumlu Python sürümü bulundu: $pythonVersion"
    } else {
        Write-Error "Python bulunamadı veya sürüm tespit edilemedi."
    }
} catch {
    Write-Host "Python yüklü değil veya PATH içinde değil." -ForegroundColor Red
    Write-Host "Lütfen https://python.org adresinden Python 3.7+ sürümünü yükleyin." -ForegroundColor Yellow
    exit 1
}

# 2. Sanal ortam oluşturma
Write-Step "Adım 2: Python Sanal Ortamı Hazırlanıyor"
$ENV_PATH = "$env:USERPROFILE\.virtualenvs\terminalai"
if (-not (Test-Path $ENV_PATH)) {
    Write-Info "Sanal ortam oluşturuluyor: $ENV_PATH"
    python -m venv $ENV_PATH
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Sanal ortam oluşturulamadı."
    }
    Write-Success "Sanal ortam başarıyla oluşturuldu."
} else {
    Write-Success "Sanal ortam zaten mevcut: $ENV_PATH"
}

# 3. Bağımlılıkları yükleme
Write-Step "Adım 3: Gerekli Python Paketleri Yükleniyor"
Write-Info "Sanal ortam aktive ediliyor ve bağımlılıklar yükleniyor..."
& "$ENV_PATH\Scripts\activate.ps1"
pip install --upgrade pip | Out-Null
pip install -r "$SCRIPT_DIR\requirements.txt"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bağımlılıklar yüklenemedi."
}
Write-Success "Tüm bağımlılıklar başarıyla yüklendi."

# 4. ai.bat sarmalayıcı (wrapper) oluşturma
Write-Step "Adım 4: Komut Sarmalayıcı (ai.bat) Oluşturuluyor"
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
Write-Success "ai.bat dosyası oluşturuldu: $batchFile"

# 5. PATH ortam değişkenine ekleme
Write-Step "Adım 5: PATH Ortam Değişkeni Güncelleniyor"
$currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
if ($currentPath -notlike "*$SCRIPT_DIR*") {
    $newPath = "$currentPath;$SCRIPT_DIR"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::User)
    Write-Success "Kullanıcı PATH değişkenine eklendi: $SCRIPT_DIR"
    Write-Info "Değişikliğin etkili olması için terminali yeniden başlatmanız gerekebilir."
} else {
    Write-Success "Dizin zaten PATH içinde mevcut: $SCRIPT_DIR"
}

# Build executable if requested
if ($BuildExe) {
    Write-Step "Adım 6: Taşınabilir EXE Dosyası Oluşturuluyor (İsteğe Bağlı)"

    # PyInstaller kontrolü
    Write-Info "PyInstaller kontrol ediliyor..."
    try {
        pyinstaller --version | Out-Null
        Write-Success "PyInstaller zaten yüklü."
    } catch {
        Write-Info "PyInstaller yükleniyor..."
        pip install pyinstaller
        if ($LASTEXITCODE -ne 0) {
            Write-Error "PyInstaller yüklenemedi."
        }
        Write-Success "PyInstaller başarıyla yüklendi."
    }

    # Temizlik
    if ($Clean) {
        Write-Info "Eski derleme dosyaları temizleniyor..."
        if (Test-Path $BUILD_DIR) { Remove-Item -Recurse -Force $BUILD_DIR; Write-Info "Silindi: $BUILD_DIR" }
        if (Test-Path $DIST_DIR) { Remove-Item -Recurse -Force $DIST_DIR; Write-Info "Silindi: $DIST_DIR" }
        if (Test-Path "$SCRIPT_DIR\ai.spec") { Remove-Item "$SCRIPT_DIR\ai.spec"; Write-Info "Silindi: ai.spec" }
        Write-Success "Temizlik tamamlandı."
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
    Write-Info "EXE dosyası oluşturuluyor... (Bu işlem biraz zaman alabilir)"
    if ($OneFile) {
        pyinstaller --onefile --console ai.py
    } else {
        pyinstaller ai.spec
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "EXE oluşturma işlemi başarısız oldu!"
    }

    # Sonuç
    $exePath = "$DIST_DIR\ai.exe"
    if (Test-Path $exePath) {
        $fileSize = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
        Write-Success "EXE başarıyla oluşturuldu!"
        Write-Info "Dosya: $exePath"
        Write-Info "Boyut: $fileSize MB"
        
        # Test
        Write-Info "Oluşturulan EXE test ediliyor..."
        try {
            & $exePath "--help" | Out-Null
            Write-Success "EXE testi başarılı."
        } catch {
            Write-Host "[UYARI] EXE testi başarısız oldu." -ForegroundColor Yellow
        }
        
        # C:\TerminalAI dizinine kopyalama
        Write-Step "Adım 7: EXE Dosyası Sistem Geneli Kullanım İçin Kopyalanıyor"
        if (-not (Test-Path $INSTALL_DIR)) {
            Write-Info "Dizin oluşturuluyor: $INSTALL_DIR"
            New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
            Write-Success "Dizin başarıyla oluşturuldu."
        }
        
        Write-Info "ai.exe dosyası $INSTALL_DIR dizinine kopyalanıyor..."
        Copy-Item -Path $exePath -Destination $INSTALL_DIR -Force
        Copy-Item "$SCRIPT_DIR\dangerous_patterns.txt" "$INSTALL_DIR\dangerous_patterns.txt" -Force
        Copy-Item "$SCRIPT_DIR\safe_patterns.txt" "$INSTALL_DIR\safe_patterns.txt" -Force
        
        # C:\TerminalAI'ı PATH'e ekleme
        Write-Info "Sistem PATH değişkeni güncelleniyor..."
        $machinePath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
        if ($machinePath -notlike "*$INSTALL_DIR*") {
            $newMachinePath = "$machinePath;$INSTALL_DIR"
            # Bu komut yönetici izni gerektirir.
            try {
                Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment' -Name 'Path' -Value $newMachinePath
                Write-Success "Sistem PATH değişkenine eklendi: $INSTALL_DIR"
                Write-Info "Değişikliğin etkili olması için terminali yeniden başlatmanız gerekebilir."
            } catch {
                Write-Host "[UYARI] Sistem PATH'i güncellenemedi. Lütfen PowerShell'i yönetici olarak çalıştırın veya manuel olarak ekleyin: $INSTALL_DIR" -ForegroundColor Yellow
            }
        } else {
            Write-Success "Dizin zaten sistem PATH içinde mevcut: $INSTALL_DIR"
        }
    } else {
        Write-Error "Oluşturulan EXE dosyası bulunamadı: $exePath"
    }
}

Write-Host "`nKurulum Tamamlandı!" -ForegroundColor Green
Write-Host "Kullanmaya başlamak için yeni bir terminal açın ve 'ai <sorunuz>' yazın."

Write-Host ""
Write-Host "Note: You'll be prompted for your OpenAI API key on first run" -ForegroundColor Yellow
Write-Host "Please restart your terminal or run: refreshenv" -ForegroundColor Yellow 