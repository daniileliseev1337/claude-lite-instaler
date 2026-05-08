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
if ($claudeCheck) {
    $version = & claude --version 2>&1
    Write-Host ""
    Write-Host "claude installed: $version" -ForegroundColor Green
    Write-Host "Path: $($claudeCheck.Path)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next: log in via 'claude auth login' (browser flow)." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: close and re-open PowerShell so PATH is picked up" -ForegroundColor Yellow
    Write-Host "in fresh terminals (current session is OK)." -ForegroundColor Yellow
}
else {
    Write-Host "claude not found in PATH after install." -ForegroundColor Yellow
    Write-Host "Try closing and re-opening PowerShell, then run 'claude --version'." -ForegroundColor Yellow
    exit 1
}
