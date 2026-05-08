<#
.SYNOPSIS
Installs uv (Python package manager) without admin rights.

.DESCRIPTION
uv is needed to run Python-based MCP servers via uvx command.
Official installer downloads to %USERPROFILE%\.local\bin\.
Adds to User PATH.

Usage on a corporate Windows PC behind proxy:
  1. Set $env:HTTPS_PROXY before running (Start-Claude-Stroy.ps1 typically does this).
  2. .\Install-UV.ps1
  3. After success, close and re-open PowerShell to pick up PATH.
#>

$ErrorActionPreference = "Stop"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Check if already installed
$uvCheck = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCheck) {
    $version = & uv --version 2>&1
    Write-Host "uv already installed: $version" -ForegroundColor Green
    Write-Host "Path: $($uvCheck.Path)" -ForegroundColor Gray
    exit 0
}

# Check proxy
if (-not $env:HTTPS_PROXY) {
    Write-Host "WARNING: HTTPS_PROXY is not set." -ForegroundColor Yellow
    Write-Host "If you are behind a corporate proxy, set HTTPS_PROXY first." -ForegroundColor Yellow
    Write-Host ""
    $resp = Read-Host "Continue anyway? (y/n)"
    if ($resp -ne "y") { exit 0 }
}

Write-Host "Installing uv via official installer..." -ForegroundColor Cyan
Write-Host "Source: https://astral.sh/uv/install.ps1" -ForegroundColor Gray
Write-Host ""

try {
    # Proxy auth via [System.Net.WebRequest]::DefaultWebProxy (set by Set-Proxy.ps1).
    # Do NOT pass -Proxy: PS 5.1 .NET Framework does not parse user:pass@host
    # from a URL-based -Proxy reliably and returns 407.
    $script = Invoke-RestMethod -Uri "https://astral.sh/uv/install.ps1"
    Invoke-Expression $script
}
catch {
    Write-Host "Install failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual fallback: download zip from https://github.com/astral-sh/uv/releases/latest" -ForegroundColor Yellow
    Write-Host "and extract to $env:USERPROFILE\.local\bin\" -ForegroundColor Yellow
    exit 1
}

# Refresh PATH after install
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Verify
$uvCheck = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCheck) {
    $version = & uv --version 2>&1
    Write-Host ""
    Write-Host "uv installed: $version" -ForegroundColor Green
    Write-Host "Path: $($uvCheck.Path)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Now uvx is available for MCP servers." -ForegroundColor Cyan
    Write-Host "Next step: run Setup-MCP-Servers.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: close and re-open PowerShell so PATH is picked up" -ForegroundColor Yellow
    Write-Host "in fresh terminals (current session is OK)." -ForegroundColor Yellow
}
else {
    Write-Host "uv not found in PATH after install." -ForegroundColor Yellow
    Write-Host "Try closing and re-opening PowerShell, then run 'uv --version'." -ForegroundColor Yellow
    exit 1
}
