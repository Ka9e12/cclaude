# cclaude installer - Run once in PowerShell: .\install.ps1
$ErrorActionPreference = "Stop"

$InstallDir = "$env:USERPROFILE\.cclaude"
$ScriptDest = "$InstallDir\cclaude.sh"
$ProvidersDir = "$env:USERPROFILE\.claude-providers"

Write-Host "=== cclaude setup ===" -ForegroundColor Cyan
Write-Host ""

# --- 1. Check Python ---
Write-Host "[1/6] Checking Python..." -NoNewline
$PythonCmd = $null
foreach ($cmd in @("py", "python", "python3")) {
    try {
        $null = & $cmd -c "import sqlite3" 2>$null
        if ($LASTEXITCODE -eq 0) { $PythonCmd = $cmd; break }
    } catch {}
}
if (-not $PythonCmd) {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Please install Python from https://python.org and retry." -ForegroundColor Red
    exit 1
}
Write-Host " OK ($PythonCmd)" -ForegroundColor Green

# --- 2. Check Git Bash ---
Write-Host "[2/6] Checking Git Bash..." -NoNewline
$BashPath = $null
# Try PATH first
try { $BashPath = (Get-Command bash -ErrorAction Stop).Source } catch {}
# Try common Git for Windows locations
if (-not $BashPath) {
    foreach ($p in @(
        "$env:ProgramFiles\Git\bin\bash.exe",
        "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:USERPROFILE\scoop\apps\git\current\bin\bash.exe"
    )) {
        if (Test-Path $p) { $BashPath = $p; break }
    }
}
if (-not $BashPath) {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Please install Git from https://git-scm.com and retry." -ForegroundColor Red
    exit 1
}
Write-Host " OK ($BashPath)" -ForegroundColor Green

# --- 3. Check Claude Code ---
Write-Host "[3/6] Checking Claude Code CLI..." -NoNewline
try {
    $null = Get-Command claude -ErrorAction Stop
    Write-Host " OK" -ForegroundColor Green
} catch {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Install with: npm install -g @anthropic-ai/claude-code" -ForegroundColor Red
    exit 1
}

# --- 4. Check cc-switch ---
Write-Host "[4/6] Checking cc-switch database..." -NoNewline
$DbPath = "$env:USERPROFILE\.cc-switch\cc-switch.db"
if (Test-Path $DbPath) {
    Write-Host " OK" -ForegroundColor Green
} else {
    Write-Host " NOT FOUND" -ForegroundColor Red
    Write-Host "  Please install and configure cc-switch first." -ForegroundColor Red
    exit 1
}

# --- 5. Install script ---
Write-Host "[5/6] Installing script..." -NoNewline
$ScriptSource = Join-Path $PSScriptRoot "cclaude.sh"
if (-not (Test-Path $ScriptSource)) {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "  cclaude.sh not found next to install.ps1. Make sure both files are in the same folder." -ForegroundColor Red
    exit 1
}

$NeedCopy = $true
if (Test-Path $ScriptDest) {
    $Existing = Get-FileHash $ScriptDest -Algorithm SHA256
    $Source = Get-FileHash $ScriptSource -Algorithm SHA256
    if ($Existing.Hash -eq $Source.Hash) {
        $NeedCopy = $false
    }
}

if ($NeedCopy) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item $ScriptSource $ScriptDest -Force
    Write-Host " Installed" -ForegroundColor Green
} else {
    Write-Host " Already up-to-date (skipped)" -ForegroundColor Yellow
}

# --- 6. Register PowerShell function ---
Write-Host "[6/6] Registering PowerShell function..." -NoNewline
$ProfileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

# Convert to Windows path with forward slashes for bash
$BashScriptPath = ($ScriptDest -replace '\\', '/')
$FuncLine = "function cclaude { & `"$BashPath`" `"$BashScriptPath`" @args }"

if (Test-Path $PROFILE) {
    $Content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($Content -match "function cclaude") {
        # Remove old function (single-line or multi-line) and add new one
        $Content = $Content -replace "(?s)function cclaude\s*\{.*?\}", ""
        $Content = $Content.TrimEnd() + "`n$FuncLine`n"
        Set-Content $PROFILE $Content -NoNewline
        Write-Host " Updated" -ForegroundColor Green
    } else {
        Add-Content $PROFILE "`n$FuncLine"
        Write-Host " Added" -ForegroundColor Green
    }
} else {
    Set-Content $PROFILE $FuncLine
    Write-Host " Created" -ForegroundColor Green
}

# --- Initial sync ---
Write-Host ""
Write-Host "Running initial sync..." -ForegroundColor Cyan
& $BashPath $ScriptDest --sync

Write-Host ""
Write-Host "=== Setup complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor White
Write-Host "  cclaude              # Interactive selection"
Write-Host "  cclaude deepseek     # Quick launch"
Write-Host "  cclaude -l           # List providers"
Write-Host "  cclaude -s           # Re-sync after adding providers in cc-switch"
Write-Host ""
if ($host.Name -eq "ConsoleHost") {
    Write-Host "Run this to activate in current window:" -ForegroundColor Yellow
    Write-Host "  . `$PROFILE" -ForegroundColor White
} else {
    Write-Host "Open a new PowerShell window to start using cclaude." -ForegroundColor Yellow
}
