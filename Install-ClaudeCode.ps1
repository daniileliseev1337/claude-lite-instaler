<#
.SYNOPSIS
Installs Claude Code CLI without admin rights.

.DESCRIPTION
Runs the official installer from Anthropic:
  irm https://claude.ai/install.ps1 | iex

Installs to "%USERPROFILE%\.local\bin\claude.exe" (no admin needed).
Standalone binary, ~250 MB.

If $env:HTTPS_PROXY is set, the installer script is fetched via the
proxy. The installer itself then downloads the binary; if it fails,
see the manual fallback section in README.md (Negotiate proxies are
known to break this path - see cases/claude-code-corp-proxy-setup.md
in the source base).
#>

$ErrorActionPreference = "Stop"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Already installed?
$claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCheck) {
    $version = & claude --version 2>&1
    Write-Host "claude already installed: $version" -ForegroundColor Green
    Write-Host "Path: $($claudeCheck.Path)" -ForegroundColor Gray
    exit 0
}

# Proxy check (informational)
if (-not $env:HTTPS_PROXY) {
    Write-Host "WARNING: HTTPS_PROXY is not set." -ForegroundColor Yellow
    Write-Host "If you are behind a corporate proxy, set it first via Set-Proxy.ps1." -ForegroundColor Yellow
    Write-Host ""
    $resp = Read-Host "Continue anyway? (y/n)"
    if ($resp -ne "y") { exit 0 }
}

Write-Host "Installing Claude Code via official installer..." -ForegroundColor Cyan
Write-Host "Source: https://claude.ai/install.ps1" -ForegroundColor Gray
Write-Host "Target: $env:USERPROFILE\.local\bin\claude.exe (~250 MB)" -ForegroundColor Gray
Write-Host ""

try {
    # Proxy auth via [System.Net.WebRequest]::DefaultWebProxy (set by Set-Proxy.ps1).
    # Do NOT pass -Proxy: see comment in Install-VSCode.ps1.
    $script = Invoke-RestMethod -Uri "https://claude.ai/install.ps1"
    Invoke-Expression $script
}
catch {
    Write-Host "Install failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual fallback:" -ForegroundColor Yellow
    Write-Host "  - download standalone binary from https://github.com/anthropics/claude-code/releases" -ForegroundColor Yellow
    Write-Host "  - extract claude.exe into $env:USERPROFILE\.local\bin\" -ForegroundColor Yellow
    Write-Host "  - add that folder to User PATH (System Properties -> Environment Variables)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "If proxy authentication is Negotiate/Kerberos, this irm path is known not to work." -ForegroundColor Yellow
    Write-Host "Use the gh api + tarball approach (see README.md, section 'Corporate proxy notes')." -ForegroundColor Yellow
    exit 1
}

# Refresh PATH after install
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Verify
$claudeCheck = Get-Command claude -ErrorAction SilentlyContinue

# The official installer sometimes does NOT add ~/.local/bin to the User
# PATH (observed on corp Win11). The binary exists but is unreachable, so
# downstream stages (Stage 6 MCP servers, Stage 8 setup-extras) fail with
# 'claude not found'. If the exe is there but not on PATH, add the folder
# ourselves -- both to the persistent User PATH (fresh terminals) and to
# THIS process PATH (so the remaining install stages in this run see it).
if (-not $claudeCheck) {
    $localBin  = Join-Path $env:USERPROFILE ".local\bin"
    $claudeExe = Join-Path $localBin "claude.exe"
    if (Test-Path $claudeExe) {
        $curUser = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($curUser -notlike "*$localBin*") {
            [Environment]::SetEnvironmentVariable("Path", "$curUser;$localBin", "User")
            Write-Host "Added $localBin to User PATH (official installer omitted it)." -ForegroundColor Yellow
        }
        $env:Path = "$env:Path;$localBin"
        $claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
    }
}

if ($claudeCheck) {
    $version = & claude --version
    Write-Host ""
    Write-Host "claude installed: $version" -ForegroundColor Green
    Write-Host "Path: $($claudeCheck.Path)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next: log in via 'claude auth login' (browser flow)." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: open a fresh terminal later so PATH is picked up everywhere" -ForegroundColor Yellow
    Write-Host "(this install run already has claude on PATH for the next stages)." -ForegroundColor Yellow
}
else {
    Write-Host "claude.exe not found after install (binary missing, not just PATH)." -ForegroundColor Yellow
    Write-Host "See manual fallback above; then re-run Install.ps1." -ForegroundColor Yellow
    exit 1
}
