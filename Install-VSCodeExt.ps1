<#
.SYNOPSIS
Installs the Anthropic Claude Code extension into VS Code.

.DESCRIPTION
Runs:
  code --install-extension anthropic.claude-code

The marketplace download will use system / VS Code proxy settings.
If VS Code is currently running, the extension is queued and activates
on next restart.

If 'code' is not in PATH (fresh VS Code install in this session),
falls back to the absolute path "%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd".
#>

$ErrorActionPreference = "Stop"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Locate code
$codeCmd = $null
$codeCheck = Get-Command code -ErrorAction SilentlyContinue
if ($codeCheck) {
    $codeCmd = $codeCheck.Path
}
else {
    $fallback = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
    if (Test-Path $fallback) {
        $codeCmd = $fallback
        Write-Host "Using fallback path: $codeCmd" -ForegroundColor Gray
    }
    else {
        Write-Host "VS Code 'code' command not found." -ForegroundColor Red
        Write-Host "Install VS Code first (Install-VSCode.ps1), or open and close a new PowerShell." -ForegroundColor Yellow
        exit 1
    }
}

$extId = "anthropic.claude-code"

# Already installed?  (2>$null drops stderr; NEVER 2>&1 -- code.cmd/node
# emit DeprecationWarnings to stderr that 2>&1 would wrap in
# NativeCommandError under ErrorActionPreference='Stop' and abort.)
$listed = & $codeCmd --list-extensions 2>$null
if ($LASTEXITCODE -eq 0 -and ($listed -contains $extId)) {
    Write-Host "Extension '$extId' already installed." -ForegroundColor Green
    exit 0
}

Write-Host "Installing VS Code extension: $extId" -ForegroundColor Cyan
Write-Host "(Marketplace download uses VS Code proxy settings.)" -ForegroundColor Gray

# NO 2>&1: code.cmd (node) prints DeprecationWarnings to stderr; under
# ErrorActionPreference='Stop' the 2>&1 merge wraps each line in
# NativeCommandError and aborts mid-install. Let output flow to the
# console; rely on $LASTEXITCODE for the success decision.
& $codeCmd --install-extension $extId

if ($LASTEXITCODE -eq 0) {
    Write-Host "Extension installed." -ForegroundColor Green
    Write-Host "Restart VS Code (or reload window) to activate." -ForegroundColor Yellow
}
else {
    Write-Host "Install failed (exit $LASTEXITCODE)." -ForegroundColor Red
    Write-Host ""
    Write-Host "Manual fallback:" -ForegroundColor Yellow
    Write-Host "  1. Open VS Code, Ctrl+Shift+X (Extensions panel)" -ForegroundColor Yellow
    Write-Host "  2. Search 'Claude Code' (publisher: Anthropic)" -ForegroundColor Yellow
    Write-Host "  3. Click Install" -ForegroundColor Yellow
    exit 1
}
