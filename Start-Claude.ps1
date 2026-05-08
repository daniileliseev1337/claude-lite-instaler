# ============================================================
#  Start-Claude.ps1
#  Двухшаговый запуск с выбором режима:
#   1) ставит прокси через Set-Proxy.ps1
#      (читает ~/.claude-proxy.json, спрашивает только пароль inline)
#   2) спрашивает: CLI (claude в этом окне) или VSCode (открыть редактор)
#
#  CLI режим:    claude запускается в этом же окне PS, прокси активен.
#  VSCode режим: VS Code открывается, наследует $env:HTTPS_PROXY.
#                После закрытия редактора - нажать любую клавишу,
#                прокси очистится, окно можно закрыть.
#
#  Параметр -Mode CLI / -Mode VSCode пропускает диалог выбора.
# ============================================================

[CmdletBinding()]
param(
    [ValidateSet("CLI", "VSCode", "")]
    [string]$Mode = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# === Step 1: proxy =================================================
& (Join-Path $here "Set-Proxy.ps1")

if (-not $env:HTTPS_PROXY) {
    Write-Host ""
    Write-Host "Proxy not set, aborting." -ForegroundColor Red
    return
}

# === Step 2: locate claude.exe =====================================
$claude = "$env:USERPROFILE\.local\bin\claude.exe"
if (-not (Test-Path $claude)) {
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $claude = $claudeCmd.Path
    }
    else {
        Write-Host ""
        Write-Host "claude.exe not found. Run Install-ClaudeCode.ps1 first." -ForegroundColor Red
        return
    }
}

# === Step 3: choose mode ===========================================
if (-not $Mode) {
    Write-Host ""
    Write-Host "Choose launch mode:" -ForegroundColor Cyan
    Write-Host "  1) CLI    - claude in this terminal"
    Write-Host "  2) VSCode - open VS Code (Claude Code extension)"
    Write-Host ""
    do {
        $resp = Read-Host "Mode (1/2)"
    } while ($resp -ne "1" -and $resp -ne "2")
    $Mode = if ($resp -eq "1") { "CLI" } else { "VSCode" }
}

# === Step 4: launch ================================================
if ($Mode -eq "CLI") {
    Write-Host ""
    Write-Host "Launching Claude Code (CLI)..." -ForegroundColor Cyan
    Write-Host ""
    & $claude
}
else {
    # VSCode mode - find Code.exe
    $codeExe = $null
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles}\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $codeExe = $c
            break
        }
    }

    if (-not $codeExe) {
        Write-Host "VS Code (Code.exe) not found in standard locations." -ForegroundColor Red
        Write-Host "Searched:" -ForegroundColor Yellow
        $candidates | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
        return
    }

    Write-Host ""
    Write-Host "Opening VS Code..." -ForegroundColor Cyan
    Write-Host "VS Code path: $codeExe" -ForegroundColor Gray
    Write-Host "VS Code will inherit HTTPS_PROXY from this session." -ForegroundColor Gray
    Write-Host ""

    Start-Process -FilePath $codeExe

    Write-Host "VS Code launched." -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Yellow
    Write-Host "  This PowerShell window keeps proxy alive in memory." -ForegroundColor Gray
    Write-Host "  After closing VS Code, also close this window" -ForegroundColor Gray
    Write-Host "  to flush proxy credentials from environment." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press any key to clear proxy from this session..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    [System.Net.WebRequest]::DefaultWebProxy = $null
    Write-Host "Proxy cleared." -ForegroundColor Green
}
