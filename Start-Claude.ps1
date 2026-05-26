# ============================================================
#  Start-Claude.ps1
#  Двухшаговый запуск с выбором режима:
#   1) ставит прокси через Set-Proxy.ps1
#      (читает ~/.claude-proxy.json, спрашивает только пароль inline)
#   2) спрашивает: CLI / VSCode / Desktop
#
#  CLI режим:     claude.exe (CLI) запускается в этом же окне PS, прокси активен.
#  VSCode режим:  VS Code открывается, наследует $env:HTTPS_PROXY.
#  Desktop режим: Claude Code Desktop (LOCALAPPDATA\AnthropicClaude\claude.exe)
#                 запускается отдельным процессом, наследует $env:HTTPS_PROXY.
#  VSCode/Desktop: после закрытия Claude — нажать любую клавишу в этом окне,
#                  прокси-credentials очистятся, окно можно закрыть.
#
#  Параметр -Mode CLI / VSCode / Desktop пропускает диалог выбора.
# ============================================================

[CmdletBinding()]
param(
    [ValidateSet("CLI", "VSCode", "Desktop", "")]
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

# === Step 2: choose mode ===========================================
if (-not $Mode) {
    Write-Host ""
    Write-Host "Choose launch mode:" -ForegroundColor Cyan
    Write-Host "  1) CLI     - claude.exe in this terminal"
    Write-Host "  2) VSCode  - open VS Code (Claude Code extension)"
    Write-Host "  3) Desktop - open Claude Code Desktop (native app)"
    Write-Host ""
    do {
        $resp = Read-Host "Mode (1/2/3)"
    } while ($resp -ne "1" -and $resp -ne "2" -and $resp -ne "3")
    $Mode = switch ($resp) {
        "1" { "CLI" }
        "2" { "VSCode" }
        "3" { "Desktop" }
    }
}

# === Step 3: launch ================================================
if ($Mode -eq "CLI") {
    # Locate claude CLI (нужно только в CLI режиме)
    $claude = "$env:USERPROFILE\.local\bin\claude.exe"
    if (-not (Test-Path $claude)) {
        $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
        if ($claudeCmd) {
            $claude = $claudeCmd.Path
        }
        else {
            Write-Host ""
            Write-Host "claude.exe (CLI) not found. Run Install-ClaudeCode.ps1 first." -ForegroundColor Red
            return
        }
    }

    Write-Host ""
    Write-Host "Launching Claude Code (CLI)..." -ForegroundColor Cyan
    Write-Host ""
    & $claude
}
elseif ($Mode -eq "Desktop") {
    # Desktop mode - find Claude Code Desktop
    $desktopExe = "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"
    if (-not (Test-Path $desktopExe)) {
        Write-Host ""
        Write-Host "Claude Code Desktop not found at:" -ForegroundColor Red
        Write-Host "  $desktopExe" -ForegroundColor Yellow
        Write-Host "Install via 'Claude Setup.exe' (no admin OK - Cowork not needed)." -ForegroundColor Yellow
        Write-Host "Прямой URL: https://api.anthropic.com/api/desktop/win32/x64/msix/latest/redirect" -ForegroundColor Gray
        return
    }

    Write-Host ""
    Write-Host "Opening Claude Code Desktop..." -ForegroundColor Cyan
    Write-Host "Desktop path: $desktopExe" -ForegroundColor Gray
    Write-Host "Claude Desktop will inherit HTTPS_PROXY from this session." -ForegroundColor Gray
    Write-Host ""

    Start-Process -FilePath $desktopExe

    Write-Host "Claude Code Desktop launched." -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT:" -ForegroundColor Yellow
    Write-Host "  This PowerShell window keeps proxy alive in memory." -ForegroundColor Gray
    Write-Host "  After closing Claude Desktop, also close this window" -ForegroundColor Gray
    Write-Host "  to flush proxy credentials from environment." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Press any key to clear proxy from this session..." -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    [System.Net.WebRequest]::DefaultWebProxy = $null
    Write-Host "Proxy cleared." -ForegroundColor Green
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
