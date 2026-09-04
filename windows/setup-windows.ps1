# sanblueᵈᵒᵗ VoiceFlow — Windows setup and Gate 5 preparation
# Run in PowerShell: powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
#
# Two kinds of result. A hard error stops the script: without it nothing further can be
# trusted. A missing prerequisite is collected and reported at the end, because knowing
# all four at once is worth more than discovering them one run at a time.

$missing = @()

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " sanblue.dot VoiceFlow - Windows environment setup " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."

# 1. Python
Write-Host "`n[1/7] Python 3.11 or newer..." -ForegroundColor Yellow
if (Get-Command python -ErrorAction SilentlyContinue) {
    Write-Host "Found: $(python --version)" -ForegroundColor Green
} else {
    Write-Host "ERROR: python is not on PATH. Install Python 3.11 or newer." -ForegroundColor Red
    Exit 1
}

# 2. Rust
Write-Host "`n[2/7] Rust and Cargo..." -ForegroundColor Yellow
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Host "Found: $(cargo --version)" -ForegroundColor Green
} else {
    Write-Host "Not installed." -ForegroundColor Yellow
    $missing += "Rust and Cargo - the adapter cannot build. Install: winget install Rustlang.Rustup"
}

# 3. Tauri CLI. `cargo tauri` is a subcommand and is not part of Cargo.
Write-Host "`n[3/7] Tauri CLI v2..." -ForegroundColor Yellow
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    $tauriVersion = cargo tauri --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Found: $tauriVersion" -ForegroundColor Green
    } else {
        Write-Host "Not installed." -ForegroundColor Yellow
        $missing += 'Tauri CLI - `cargo tauri dev` does not exist without it. Install: cargo install tauri-cli --version "^2.0"'
    }
} else {
    Write-Host "Skipped: Cargo is missing, so the CLI cannot be checked." -ForegroundColor Yellow
}

# 4. Engine installation
Write-Host "`n[4/7] Installing the Python engine..." -ForegroundColor Yellow
Push-Location $projectRoot
python -m pip install --upgrade pip
python -m pip install -e .
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: pip install failed." -ForegroundColor Red
    Pop-Location
    Exit 1
}
Pop-Location
Write-Host "Engine installed." -ForegroundColor Green

# 5. Engine tests. Gate 5 requires the same tests to pass on this machine.
Write-Host "`n[5/7] Engine tests on Windows..." -ForegroundColor Yellow
Push-Location $projectRoot
$env:PYTHONPATH = "src"
python -m unittest discover -s tests
if ($LASTEXITCODE -ne 0) {
    Write-Host "`nERROR: the engine tests failed on Windows. Gate 5 cannot advance." -ForegroundColor Red
    Pop-Location
    Exit 1
}
Pop-Location
Write-Host "Engine tests passed on Windows." -ForegroundColor Green

# 6. Speech binary. FFmpeg's own whisper filter is a different interface and does not
# satisfy this: the engine invokes the whisper.cpp executable directly.
Write-Host "`n[6/7] whisper.cpp executable..." -ForegroundColor Yellow
$whisperBin = Join-Path $projectRoot "models\whisper-cli.exe"
if (Test-Path $whisperBin) {
    Write-Host "Found: $whisperBin" -ForegroundColor Green
} else {
    Write-Host "Not found in models\." -ForegroundColor Yellow
    $missing += "whisper-cli.exe - no local transcription. Place a prebuilt whisper.cpp Windows x64 release at models\whisper-cli.exe (https://github.com/ggerganov/whisper.cpp/releases)"
}

# 7. Model weights. `models/` is excluded from version control, so nothing arrives with
# a clone and the file has to be copied here deliberately.
Write-Host "`n[7/7] Model weights..." -ForegroundColor Yellow
$models = @(Get-ChildItem -Path (Join-Path $projectRoot "models") -Filter "*.bin" -ErrorAction SilentlyContinue)
if ($models.Count -gt 0) {
    foreach ($model in $models) {
        $sizeMb = [math]::Round($model.Length / 1MB)
        Write-Host "Found: $($model.Name) ($sizeMb MB)" -ForegroundColor Green
    }
} else {
    Write-Host "No .bin model in models\." -ForegroundColor Yellow
    $missing += "A GGML model - copy ggml-small.bin (465 MB) into models\. It is excluded from version control and does not arrive with a clone"
}

Write-Host "`n==================================================" -ForegroundColor Cyan
if ($missing.Count -eq 0) {
    Write-Host " Every prerequisite is present." -ForegroundColor Green
    Write-Host " Next: cd windows; cargo tauri dev" -ForegroundColor Cyan
    Write-Host " Expect compilation errors on the first build: this" -ForegroundColor Cyan
    Write-Host " adapter has never been compiled anywhere." -ForegroundColor Cyan
} else {
    Write-Host " The engine is installed and its tests pass." -ForegroundColor Green
    Write-Host " $($missing.Count) prerequisite(s) still missing:" -ForegroundColor Yellow
    foreach ($item in $missing) {
        Write-Host "  - $item" -ForegroundColor Yellow
    }
}
Write-Host "==================================================" -ForegroundColor Cyan
