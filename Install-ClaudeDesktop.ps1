<#
.SYNOPSIS
Installs Claude Code Desktop (native app) without admin rights.

.DESCRIPTION
Downloads the official Anthropic installer:
  https://claude.ai/api/desktop/win32/x64/setup/latest/redirect

Installs into %LOCALAPPDATA%\AnthropicClaude\ (per-user, no admin needed).
~150 MB. UAC will ask for admin: choose "Install Without Admin" to skip
the Cowork feature (not needed for our setup) and continue installation.

If $env:HTTPS_PROXY is set, the file is downloaded via the proxy.

After install, the app can be launched via:
  - Start menu shortcut "Claude"
  - Start-Claude.bat -> Mode 3 (Desktop) with corporate proxy
#>

$ErrorActionPreference = "Stop"

# === Already installed? ============================================
$installedExe = "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"
if (Test-Path $installedExe) {
    $verInfo = (Get-Item $installedExe).VersionInfo
    Write-Host "Claude Code Desktop already installed:" -ForegroundColor Green
    Write-Host "  Path:    $installedExe" -ForegroundColor Gray
    Write-Host "  Version: $($verInfo.FileVersion)" -ForegroundColor Gray
    Write-Host ""
    $resp = Read-Host "Reinstall / update? (y/n)"
    if ($resp -ne "y" -and $resp -ne "Y") {
        Write-Host "Skipped." -ForegroundColor Yellow
        exit 0
    }
}

# === Proxy check (informational) ===================================
if (-not $env:HTTPS_PROXY) {
    Write-Host "WARNING: HTTPS_PROXY is not set." -ForegroundColor Yellow
    Write-Host "If you are behind a corporate proxy, set it first via Set-Proxy.ps1." -ForegroundColor Yellow
    Write-Host ""
    $resp = Read-Host "Continue anyway? (y/n)"
    if ($resp -ne "y" -and $resp -ne "Y") { exit 0 }
}

# === Download installer ============================================
$downloadUrl = "https://claude.ai/api/desktop/win32/x64/setup/latest/redirect"
$setupPath = Join-Path $env:TEMP "ClaudeSetup.exe"

# Clean up stale download from previous attempt
if (Test-Path $setupPath) {
    Remove-Item $setupPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Downloading Claude Code Desktop installer..." -ForegroundColor Cyan
Write-Host "  Source: $downloadUrl" -ForegroundColor Gray
Write-Host "  Target: $setupPath (~150 MB)" -ForegroundColor Gray
if ($env:HTTPS_PROXY) {
    Write-Host "  Via proxy: $env:HTTPS_PROXY" -ForegroundColor Gray
}
Write-Host ""

try {
    # Proxy auth via [System.Net.WebRequest]::DefaultWebProxy (set by Set-Proxy.ps1).
    # Do NOT pass -Proxy explicitly: same gotcha as in Install-VSCode.ps1.
    $ProgressPreference = 'SilentlyContinue'  # speed up Invoke-WebRequest on large files
    Invoke-WebRequest -Uri $downloadUrl -OutFile $setupPath -UseBasicParsing
    $ProgressPreference = 'Continue'

    if (-not (Test-Path $setupPath)) {
        throw "Download finished but file not found at $setupPath"
    }

    $sizeMB = [math]::Round((Get-Item $setupPath).Length / 1MB, 1)
    Write-Host "Downloaded: $sizeMB MB" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Download failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual fallback:" -ForegroundColor Yellow
    Write-Host "  1. Open in browser: https://claude.com/download" -ForegroundColor Yellow
    Write-Host "  2. Download Windows installer manually." -ForegroundColor Yellow
    Write-Host "  3. Run downloaded ClaudeSetup.exe -- the rest of this script's" -ForegroundColor Yellow
    Write-Host "     instructions still apply (Install Without Admin, etc)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If proxy authentication is Negotiate/Kerberos, this irm path is known not to work." -ForegroundColor Yellow
    exit 1
}

# === Run installer (interactive UAC) ===============================
Write-Host ""
Write-Host "Launching ClaudeSetup.exe..." -ForegroundColor Cyan
Write-Host ""
Write-Host "===== UAC PROMPT INSTRUCTIONS =====" -ForegroundColor Yellow
Write-Host "  1. Windows UAC dialog will ask for ADMIN credentials." -ForegroundColor White
Write-Host "  2. If you DO NOT have domain admin -> click 'Net' / 'No'." -ForegroundColor White
Write-Host "  3. Fallback dialog 'Install Without Admin' appears -> click 'Da' / 'Yes'." -ForegroundColor White
Write-Host "  4. This skips Cowork (team realtime collab) but installs all other features." -ForegroundColor White
Write-Host "  5. Wait for the Squirrel installer to extract files (~30 seconds)." -ForegroundColor White
Write-Host "===================================" -ForegroundColor Yellow
Write-Host ""

& $setupPath

# === Verify install ================================================
# Give Squirrel a moment to extract files
Start-Sleep -Seconds 5

if (Test-Path $installedExe) {
    $verInfo = (Get-Item $installedExe).VersionInfo
    Write-Host ""
    Write-Host "Claude Code Desktop installed:" -ForegroundColor Green
    Write-Host "  Path:    $installedExe" -ForegroundColor Gray
    Write-Host "  Version: $($verInfo.FileVersion)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next: launch via Start menu shortcut 'Claude'" -ForegroundColor Cyan
    Write-Host "Or via Start-Claude.bat -> Mode 3 (Desktop) for corp-proxy startup." -ForegroundColor Cyan
}
else {
    Write-Host ""
    Write-Host "claude.exe not found at expected location:" -ForegroundColor Yellow
    Write-Host "  $installedExe" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Yellow
    Write-Host "  - Setup is still extracting in background -- check Task Manager." -ForegroundColor White
    Write-Host "  - User cancelled UAC and 'Install Without Admin' dialog." -ForegroundColor White
    Write-Host "  - Setup chose a different install path (rare)." -ForegroundColor White
    Write-Host ""
    Write-Host "Wait 30 seconds then re-check: Test-Path '$installedExe'" -ForegroundColor Yellow
}

# === Cleanup setup file ============================================
try {
    Remove-Item $setupPath -Force -ErrorAction SilentlyContinue
} catch { }
