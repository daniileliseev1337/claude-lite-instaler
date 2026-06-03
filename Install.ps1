<#
.SYNOPSIS
Lite installer for Claude Code workstation: VS Code + extension + CLI +
proxy + uv + MCP servers + ~/.claude/ синхронизированный с claude-base.
No admin rights required.

.DESCRIPTION
Step-by-step orchestrator. Asks before each stage:

  1. Proxy           Set HTTP_PROXY / HTTPS_PROXY for current session.
                     Затем (не интерактивно) копирует proxy-хелперы
                     (Set-Proxy.ps1, Start-Claude.bat/ps1/ahk) в
                     ~/.claude/bin/ и создаёт ярлык в Пуске
                     "Claude (with proxy)". Урок 15.
  2. VS Code         User installer, silent, %LOCALAPPDATA%\Programs\.
  3. Claude Code CLI Official installer, %USERPROFILE%\.local\bin\.
  4. VS Code ext     anthropic.claude-code from Marketplace.
  5. uv              Python package manager (needed for uvx / MCP).
  6. MCP servers     8 user-scope servers via 'claude mcp add'.
  7. claude-base sync ~/.claude/ становится git-рабочей-копией claude-base
                     (CLAUDE.md, agents, skills, memory, sessions, harvested).
  8. Setup extras    Python 3.12 + 7 Python pkgs (matplotlib, ezdxf, paddleocr...)
                     + autocad-mcp (GitHub clone + uv sync + claude mcp add)
                     по ~/.claude/mcp-manifest.json. Идемпотентно.
  9. Claude Desktop  (Optional) Native Claude Code Desktop app, per-user install
                     via https://claude.ai/api/desktop/win32/x64/setup/latest/redirect.
                     Альтернатива VS Code extension для тех кто хочет отдельное
                     приложение. Запускается через Start-Claude.bat -> Mode 3.

Что этот установщик НЕ делает:
  - не клонирует другие репозитории, не настраивает push в чужие remote
  - не запрашивает права администратора
  - не трогает credentials, history, plugins, projects пользователя

Parameters:
  -Yes  skip per-step prompts (assume "yes" everywhere)

Corporate proxy notes:
  Stages 2-6 download from the Internet. Stage 7 делает git clone /
  pull — пройдёт через прокси если HTTPS_PROXY выставлен (Stage 1).
  Если корпоративный прокси использует Negotiate / Kerberos — irm-стадии
  2 и 3 не пройдут. Manual fallback см. в README.md.
#>

param(
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# UTF-8 вывод — чтобы кириллица и линии рамок рендерились на любом codepage.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

function Write-Banner {
    Write-Host ""
    Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "     CLAUDE-BASE" -ForegroundColor Cyan -NoNewline
    Write-Host "  ·  Lite Installer" -ForegroundColor White
    Write-Host "     K-7 workstation · без прав админа · этапы пропускаемы" -ForegroundColor Gray
    Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
}

function Write-Section {
    param([string]$Title, [string]$Color = "Cyan")
    Write-Host ""
    $pad = [Math]::Max(4, 58 - $Title.Length)
    Write-Host "  ── $Title " -ForegroundColor $Color -NoNewline
    Write-Host ("─" * $pad) -ForegroundColor DarkCyan
}

function Confirm-Step {
    param([string]$Question)
    if ($Yes) { return $true }
    $resp = Read-Host "$Question (y/n)"
    return ($resp -eq "y" -or $resp -eq "Y")
}

function Run-Stage {
    param(
        [string]$Title,
        [string]$Description,
        [string]$Question,
        [string]$Script,
        [string[]]$Args = @()
    )
    Write-Section $Title
    Write-Host "     $Description" -ForegroundColor Gray

    if (Confirm-Step $Question) {
        $scriptPath = Join-Path $here $Script
        if ($Args.Count -gt 0) {
            & $scriptPath @Args
        } else {
            & $scriptPath
        }
    }
    else {
        Write-Host "Skipped." -ForegroundColor Yellow
    }
}

Write-Banner

Run-Stage `
    -Title       "Stage 1/9: Proxy" `
    -Description "Required if you are behind a corporate Basic-auth proxy." `
    -Question    "Set HTTP proxy for the current session?" `
    -Script      "Set-Proxy.ps1"

# === Persist proxy helpers ===========================================
# Скопировать proxy-хелперы в ~/.claude/bin/, чтобы они оставались
# доступными после удаления installer-папки. Не интерактивно: всегда,
# даже если Stage 1 пропущен (на будущее: пользователь может переехать
# в место где прокси нужен).
# Урок 15 (memory/2026-05-18_lesson-15-proxy-helpers-persistence.md).
Write-Section "Persist proxy helpers → ~/.claude/bin/"

$binDir = Join-Path $env:USERPROFILE ".claude\bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$helpers = @(
    "Set-Proxy.ps1",
    "Set-Proxy.cmd",
    "Start-Claude.ps1",
    "Start-Claude.bat",
    "Start-Claude.ahk"
)
$copied = 0
foreach ($h in $helpers) {
    $src = Join-Path $here $h
    $dst = Join-Path $binDir $h
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        $copied++
    }
}
Write-Host "  Скопировано $copied хелперов в $binDir" -ForegroundColor Gray

# Start Menu shortcut to Start-Claude.bat (одним кликом запустить Claude с прокси)
try {
    $startMenu = [Environment]::GetFolderPath("Programs")
    $shortcutPath = Join-Path $startMenu "Claude (with proxy).lnk"
    if (-not (Test-Path $shortcutPath)) {
        $startBat = Join-Path $binDir "Start-Claude.bat"
        if (Test-Path $startBat) {
            $wsh = New-Object -ComObject WScript.Shell
            $shortcut = $wsh.CreateShortcut($shortcutPath)
            $shortcut.TargetPath      = $startBat
            $shortcut.WorkingDirectory = $env:USERPROFILE
            $shortcut.IconLocation    = "$env:SystemRoot\System32\cmd.exe,0"
            $shortcut.Save()
            Write-Host "  Ярлык Пуск -> 'Claude (with proxy)'" -ForegroundColor Gray
        }
    } else {
        Write-Host "  Ярлык 'Claude (with proxy)' уже существует, пропускаю" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Не удалось создать ярлык в Пуске (не критично): $($_.Exception.Message)" -ForegroundColor Yellow
}

Run-Stage `
    -Title       "Stage 2/9: VS Code (User installer)" `
    -Description "Installs VS Code into %LOCALAPPDATA%\Programs\, no admin." `
    -Question    "Install VS Code?" `
    -Script      "Install-VSCode.ps1"

Run-Stage `
    -Title       "Stage 3/9: Claude Code CLI" `
    -Description "Official Anthropic installer. Standalone ~250 MB binary." `
    -Question    "Install Claude Code CLI?" `
    -Script      "Install-ClaudeCode.ps1"

Run-Stage `
    -Title       "Stage 4/9: VS Code Claude extension" `
    -Description "Marketplace extension 'anthropic.claude-code'." `
    -Question    "Install Claude Code extension into VS Code?" `
    -Script      "Install-VSCodeExt.ps1"

Run-Stage `
    -Title       "Stage 5/9: uv (Python package manager)" `
    -Description "Provides 'uvx' to run the MCP servers." `
    -Question    "Install uv?" `
    -Script      "Install-UV.ps1"

Run-Stage `
    -Title       "Stage 6/9: MCP servers" `
    -Description "Adds 8 user-scope MCP servers via 'claude mcp add'." `
    -Question    "Add MCP servers?" `
    -Script      "Setup-MCP-Servers.ps1"

Run-Stage `
    -Title       "Stage 7/9: claude-base sync" `
    -Description "Makes ~/.claude/ a git working copy of claude-base (CLAUDE.md, agents, skills, memory, sessions, harvested). For existing non-git ~/.claude/ -- migration with backup, preserving credentials/history/plugins/projects." `
    -Question    "Sync ~/.claude/ with claude-base?" `
    -Script      "Apply-ClaudeMd.ps1" `
    -Args        @(if ($Yes) { '-Yes' } else { @() })

# === Stage 8: Setup extras (Python pkgs + MCP servers from manifest) ===
# Этот скрипт лежит в ~/.claude/scripts/setup-extras.ps1 -- он попал туда
# вместе с claude-base sync на предыдущем шаге. Поэтому путь не относительно
# инсталлятора, а из домашней .claude/.
Write-Section "Stage 8/9: Setup extras (manifest-driven)"
Write-Host "Устанавливает Python 3.12 (если нет) + Python user-pkgs из manifest" -ForegroundColor Gray
Write-Host "(matplotlib, ezdxf, paddleocr, ...) + autocad-mcp (GitHub clone + uv sync)." -ForegroundColor Gray
Write-Host "Идемпотентно: пропускает уже установленное. ~5-10 минут, ~500 MB диска." -ForegroundColor Gray
Write-Host "Подробнее: ~/.claude/scripts/SETUP-EXTRAS-README.md" -ForegroundColor Gray

$extrasScript = Join-Path $env:USERPROFILE ".claude\scripts\setup-extras.ps1"
$manifestFile = Join-Path $env:USERPROFILE ".claude\mcp-manifest.json"

if (-not (Test-Path $extrasScript)) {
    Write-Host "  setup-extras.ps1 не найден в ~/.claude/scripts/." -ForegroundColor Yellow
    Write-Host "  Это значит Stage 7 пропущен или упал -- ~/.claude/ ещё не синхронизирован." -ForegroundColor Yellow
    Write-Host "  Пропускаю Stage 8. Запусти заново когда Stage 7 пройдёт." -ForegroundColor Yellow
} elseif (-not (Test-Path $manifestFile)) {
    Write-Host "  mcp-manifest.json не найден -- старая версия claude-base?" -ForegroundColor Yellow
    Write-Host "  Сделай cd ~/.claude && git pull, потом запусти setup-extras.ps1 вручную." -ForegroundColor Yellow
} elseif (Confirm-Step "Run setup-extras to install Python + extra MCP servers?") {
    $extrasArgs = @()
    if ($Yes) { $extrasArgs += '-Yes' }
    & $extrasScript @extrasArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  setup-extras.ps1 exit=$LASTEXITCODE -- часть extras может быть не установлена." -ForegroundColor Yellow
        Write-Host "  Подробности: ~/.claude/auto-sync.log (записи 'setup-extras:')" -ForegroundColor Yellow
    } else {
        Write-Host "  Stage 8 OK -- extras установлены." -ForegroundColor Green
    }
} else {
    Write-Host "Skipped. Запустить позже: pwsh `"$extrasScript`"" -ForegroundColor Yellow
}

Run-Stage `
    -Title       "Stage 9/9: Claude Code Desktop (Optional)" `
    -Description "Native Claude app, per-user install (no admin). Alternative to VS Code extension. ~150 MB. Запускать потом через Start-Claude.bat -> Mode 3." `
    -Question    "Install Claude Code Desktop?" `
    -Script      "Install-ClaudeDesktop.ps1"

# === Feedback channel — заметный prompted-шаг (НЕ «опционально» в тексте) ===
Write-Section "Feedback-канал — чтобы твои уроки доходили до базы" "Green"
Write-Host "     ВСЕ машины кроме dev-хаба шлют правки/уроки в claude-base-feedback." -ForegroundColor Gray
Write-Host "     Не настроишь — работаешь «в стол», база о твоих находках не узнает." -ForegroundColor Gray
Write-Host "     Нужен PAT (Personal Access Token) — получи у Daniil'а." -ForegroundColor Gray
$updBat = Join-Path $env:USERPROFILE ".claude\scripts\Update-ClaudeBase.bat"
if (Confirm-Step "Настроить feedback-канал сейчас? (рекомендуется всем, кроме хаба)") {
    if (Test-Path $updBat) {
        Write-Host "     Запускаю Update-ClaudeBase.bat (спросит PAT, сделает smoke-test push)..." -ForegroundColor Gray
        & cmd /c "`"$updBat`""
    } else {
        Write-Host "     Update-ClaudeBase.bat не найден — Stage 7 не прошёл. Позже: ~/.claude/scripts/Update-ClaudeBase.bat" -ForegroundColor Yellow
    }
} else {
    Write-Host "     Пропущено. Включить позже — двойной клик: ~/.claude/scripts/Update-ClaudeBase.bat" -ForegroundColor Yellow
}

# === Done ===========================================================
Write-Host ""
Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkGreen
Write-Host "     ✓ Установка завершена" -ForegroundColor Green
Write-Host "  ════════════════════════════════════════════════════════" -ForegroundColor DarkGreen

Write-Section "Дальше"
Write-Host "     1. Закрой и открой PowerShell заново (PATH подхватит code/claude/uv/python)." -ForegroundColor White
Write-Host "     2. claude auth login  — вход через браузер." -ForegroundColor White
Write-Host "     3. Перезапусти Claude Code — подхватит MCP, skills, CLAUDE.md." -ForegroundColor White
Write-Host "     4. claude mcp list  — должно быть 9-10 серверов (8 базовых + adeu [+ autocad])." -ForegroundColor White
Write-Host "     5. (если есть AutoCAD) APPLOAD → ~/.claude/mcp-servers/autocad-mcp/lisp-code/mcp_dispatch.lsp" -ForegroundColor White
Write-Host "     6. ~/.claude/CLAUDE.md — свои правила в секции USER EXTENSIONS." -ForegroundColor White

Write-Section "Обновления базы"
Write-Host "     Двойной клик: ~/.claude/scripts/Update-ClaudeBase.bat" -ForegroundColor White
Write-Host "     git pull + merge settings + verify (23 проверки) + feedback push. Идемпотентно." -ForegroundColor Gray

Write-Section "Прокси и Desktop"
Write-Host "     Новый терминал: & `"$env:USERPROFILE\.claude\bin\Set-Proxy.ps1`"  или Пуск → 'Claude (with proxy)'" -ForegroundColor Gray
Write-Host "     Claude Desktop (если ставил Stage 9): Пуск → 'Claude (with proxy)' → Mode 3" -ForegroundColor Gray
Write-Host ""
