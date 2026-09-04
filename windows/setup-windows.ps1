# sanblueᵈᵒᵗ VoiceFlow — Windows Setup & Gate 5 Preparation Script
# Run in PowerShell: powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " sanblueᵈᵒᵗ VoiceFlow — Windows Environment Setup " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Check Python
Write-Host "`n[1/5] Checking Python 3.11+..." -ForegroundColor Yellow
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pyVer = python --version
    Write-Host "Found: $pyVer" -ForegroundColor Green
} else {
    Write-Host "ERROR: Python is not found in PATH. Install Python 3.11+." -ForegroundColor Red
    Exit 1
}

# 2. Check Rust & Cargo
Write-Host "`n[2/5] Checking Rust and Cargo..." -ForegroundColor Yellow
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    $cargoVer = cargo --version
    Write-Host "Found: $cargoVer" -ForegroundColor Green
} else {
    Write-Host "WARNING: Cargo/Rust is not installed. Install via https://rustup.rs if building Tauri." -ForegroundColor Yellow
}

# 3. Install Python Dependencies
Write-Host "`n[3/5] Installing VoiceFlow Python engine dependencies..." -ForegroundColor Yellow
$projectRoot = Resolve-Path "$PSScriptRoot\.."
Push-Location $projectRoot
python -m pip install --upgrade pip
python -m pip install -e .
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: pip install failed." -ForegroundColor Red
    Pop-Location
    Exit 1
}
Pop-Location
Write-Host "Python dependencies installed." -ForegroundColor Green

# 4. Verify Engine Tests on Windows (Gate 5 mandatory condition)
Write-Host "`n[4/5] Running Python engine verification tests (Gate 5 prerequisite)..." -ForegroundColor Yellow
Push-Location $projectRoot
$env:PYTHONPATH = "src"
python -m unittest discover -s tests
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nERROR: Unit tests failed on Windows. Cannot proceed to Gate 5 approval." -ForegroundColor Red
    Pop-Location
    Exit 1
}
Pop-Location
Write-Host "Engine unit tests PASSED on Windows." -ForegroundColor Green

# 5. Check whisper.cpp binary
Write-Host "`n[5/5] Checking whisper.cpp Windows executable..." -ForegroundColor Yellow
$whisperBin = "$projectRoot\models\whisper-cli.exe"
if (Test-Path $whisperBin) {
    Write-Host "Found whisper-cli.exe at $whisperBin" -ForegroundColor Green
} else {
    Write-Host "Notice: whisper-cli.exe not found in models/ folder." -ForegroundColor Yellow
    Write-Host "Download pre-built whisper.cpp Windows binary from:" -ForegroundColor Gray
    Write-Host "https://github.com/ggerganov/whisper.cpp/releases (whisper-bin-x64.zip)" -ForegroundColor Gray
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host " Setup check completed successfully! " -ForegroundColor Green
Write-Host " To start the Windows HUD: cd windows; cargo tauri dev " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
