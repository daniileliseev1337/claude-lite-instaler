<#
.SYNOPSIS
Installs Visual Studio Code (User installer) silently, no admin rights.

.DESCRIPTION
Downloads the latest stable User-installer (Inno Setup .exe) and runs
it with /VERYSILENT. Targets %LOCALAPPDATA%\Programs\Microsoft VS Code\.

If 'code' is already in PATH - exits as no-op.
Skips desktop / quick-launch icons; does NOT auto-launch VS Code.
Adds VS Code to User PATH automatically (the installer does this).

The download URL is the official Microsoft redirector:
  https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user
#>

$ErrorActionPreference = "Stop"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Already installed?
$codeCheck = Get-Command code -ErrorAction SilentlyContinue
if ($codeCheck) {
    Write-Host "VS Code already installed." -ForegroundColor Green
    Write-Host "Path: $($codeCheck.Path)" -ForegroundColor Gray
    exit 0
}

# Proxy check
if (-not $env:HTTPS_PROXY) {
    Write-Host "WARNING: HTTPS_PROXY is not set." -ForegroundColor Yellow
    $resp = Read-Host "Continue anyway? (y/n)"
    if ($resp -ne "y") { exit 0 }
}

$url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64-user"
$installerPath = Join-Path $env:TEMP "VSCodeUserSetup.exe"

Write-Host "Downloading VS Code User installer (~120 MB)..." -ForegroundColor Cyan
Write-Host "Source: $url" -ForegroundColor Gray
Write-Host "Target: $installerPath" -ForegroundColor Gray

try {
    # Proxy authentication is handled via [System.Net.WebRequest]::DefaultWebProxy,
    # which Set-Proxy.ps1 configures with explicit NetworkCredential.
    # Do NOT pass -Proxy here: it would replace DefaultWebProxy with a
    # URL-based proxy that fails to authenticate (PS 5.1 .NET Framework
    # does not parse user:pass@host from URL reliably -> 407 errors).
    Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -MaximumRedirection 5
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual fallback: download $url in a browser, then run:" -ForegroundColor Yellow
    Write-Host "  & '<downloaded-path>' /VERYSILENT /MERGETASKS=!runcode /NORESTART" -ForegroundColor Gray
    exit 1
}

if (-not (Test-Path $installerPath)) {
    Write-Host "Download completed but file not found at $installerPath" -ForegroundColor Red
    exit 1
}

$sizeMB = [math]::Round((Get-Item $installerPath).Length / 1MB, 1)
Write-Host "Downloaded: $sizeMB MB" -ForegroundColor Gray
Write-Host ""

Write-Host "Running silent install..." -ForegroundColor Cyan
Write-Host "Flags: /VERYSILENT /MERGETASKS=!runcode /NORESTART /SUPPRESSMSGBOXES" -ForegroundColor Gray

$proc = Start-Process -FilePath $installerPath `
    -ArgumentList "/VERYSILENT", "/MERGETASKS=!runcode", "/NORESTART", "/SUPPRESSMSGBOXES" `
    -PassThru -Wait

if ($proc.ExitCode -ne 0) {
    Write-Host "Installer exited with code $($proc.ExitCode)." -ForegroundColor Yellow
    Write-Host "VS Code may still have installed - verifying..." -ForegroundColor Yellow
}

# Cleanup installer
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

# Refresh PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Verify
$codeCheck = Get-Command code -ErrorAction SilentlyContinue
if ($codeCheck) {
    Write-Host ""
    Write-Host "VS Code installed." -ForegroundColor Green
    Write-Host "Path: $($codeCheck.Path)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "IMPORTANT: close and re-open PowerShell so 'code' command is available" -ForegroundColor Yellow
    Write-Host "in fresh terminals (current session is OK)." -ForegroundColor Yellow
}
else {
    $expected = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $expected) {
        Write-Host "VS Code installed at: $expected" -ForegroundColor Green
        Write-Host "PATH not picked up yet - close and re-open PowerShell." -ForegroundColor Yellow
    }
    else {
        Write-Host "VS Code not found after install." -ForegroundColor Red
        exit 1
    }
}
