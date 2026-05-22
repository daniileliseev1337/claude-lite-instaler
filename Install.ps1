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
    Write-Host ""
    Write-Host "--- $Title ---" -ForegroundColor Cyan
    Write-Host $Description -ForegroundColor Gray

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

Write-Host ""
Write-Host "=== Lite installer for Claude Code workstation ===" -ForegroundColor Cyan
Write-Host "No admin rights required. Stages are skippable." -ForegroundColor Gray

Run-Stage `
    -Title       "Stage 1/8: Proxy" `
    -Description "Required if you are behind a corporate Basic-auth proxy." `
    -Question    "Set HTTP proxy for the current session?" `
    -Script      "Set-Proxy.ps1"

# === Persist proxy helpers ===========================================
# Скопировать proxy-хелперы в ~/.claude/bin/, чтобы они оставались
# доступными после удаления installer-папки. Не интерактивно: всегда,
# даже если Stage 1 пропущен (на будущее: пользователь может переехать
# в место где прокси нужен).
# Урок 15 (memory/2026-05-18_lesson-15-proxy-helpers-persistence.md).
Write-Host ""
Write-Host "--- Persisting proxy helpers to ~/.claude/bin/ ---" -ForegroundColor Cyan

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
    -Title       "Stage 2/8: VS Code (User installer)" `
    -Description "Installs VS Code into %LOCALAPPDATA%\Programs\, no admin." `
    -Question    "Install VS Code?" `
    -Script      "Install-VSCode.ps1"

Run-Stage `
    -Title       "Stage 3/8: Claude Code CLI" `
    -Description "Official Anthropic installer. Standalone ~250 MB binary." `
    -Question    "Install Claude Code CLI?" `
    -Script      "Install-ClaudeCode.ps1"

Run-Stage `
    -Title       "Stage 4/8: VS Code Claude extension" `
    -Description "Marketplace extension 'anthropic.claude-code'." `
    -Question    "Install Claude Code extension into VS Code?" `
    -Script      "Install-VSCodeExt.ps1"

Run-Stage `
    -Title       "Stage 5/8: uv (Python package manager)" `
    -Description "Provides 'uvx' to run the MCP servers." `
    -Question    "Install uv?" `
    -Script      "Install-UV.ps1"

Run-Stage `
    -Title       "Stage 6/8: MCP servers" `
    -Description "Adds 8 user-scope MCP servers via 'claude mcp add'." `
    -Question    "Add MCP servers?" `
    -Script      "Setup-MCP-Servers.ps1"

Run-Stage `
    -Title       "Stage 7/8: claude-base sync" `
    -Description "Makes ~/.claude/ a git working copy of claude-base (CLAUDE.md, agents, skills, memory, sessions, harvested). For existing non-git ~/.claude/ -- migration with backup, preserving credentials/history/plugins/projects." `
    -Question    "Sync ~/.claude/ with claude-base?" `
    -Script      "Apply-ClaudeMd.ps1" `
    -Args        @(if ($Yes) { '-Yes' } else { @() })

# === Stage 8: Setup extras (Python pkgs + MCP servers from manifest) ===
# Этот скрипт лежит в ~/.claude/scripts/setup-extras.ps1 -- он попал туда
# вместе с claude-base sync на предыдущем шаге. Поэтому путь не относительно
# инсталлятора, а из домашней .claude/.
Write-Host ""
Write-Host "--- Stage 8/8: Setup extras (manifest-driven) ---" -ForegroundColor Cyan
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

# === Done ===========================================================
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and re-open PowerShell so PATH picks up code/claude/uv/python." -ForegroundColor White
Write-Host "  2. Run 'claude auth login' (browser flow) to log in." -ForegroundColor White
Write-Host "  3. Restart Claude Code session to load MCP servers, skills, CLAUDE.md." -ForegroundColor White
Write-Host "  4. Verify with 'claude mcp list' (should show 9-10 servers: 8 base + adeu, + autocad-mcp if AutoCAD installed)." -ForegroundColor White
Write-Host "  5. (Optional) Если установлен AutoCAD: в AutoCAD выполнить APPLOAD и загрузить" -ForegroundColor White
Write-Host "     ~/.claude/mcp-servers/autocad-mcp/lisp-code/mcp_dispatch.lsp" -ForegroundColor White
Write-Host "     Это включает полный режим autocad-mcp (без него -- только headless ezdxf)." -ForegroundColor White
Write-Host "  6. Open ~/.claude/CLAUDE.md and add personal rules in USER EXTENSIONS section." -ForegroundColor White
Write-Host ""
Write-Host "  --- Online feedback channel (опционально) ---" -ForegroundColor Cyan
Write-Host "  7. Чтобы включить общий обмен (feedback push в claude-base-feedback):" -ForegroundColor White
Write-Host "     запусти ~/.claude/scripts/Update-ClaudeBase.bat" -ForegroundColor Gray
Write-Host "     Он спросит PAT (Personal Access Token, получи у Daniil'а) и" -ForegroundColor Gray
Write-Host "     сделает smoke-test push в твою feedback ветку." -ForegroundColor Gray
Write-Host ""
Write-Host "  --- Future updates ---" -ForegroundColor Cyan
Write-Host "  8. Для будущих обновлений базы — ДВОЙНОЙ КЛИК на:" -ForegroundColor White
Write-Host "     ~/.claude/scripts/Update-ClaudeBase.bat" -ForegroundColor Gray
Write-Host "     Делает: git pull + merge shared settings + verify (23 проверки)" -ForegroundColor Gray
Write-Host "     + (consumer) smoke-test feedback push. Idempotent." -ForegroundColor Gray
Write-Host "     Альтернатива: re-run этого installer'а (он тоже git pull-ит)." -ForegroundColor Gray
Write-Host ""
Write-Host "Each new terminal needs proxy re-set:" -ForegroundColor White
Write-Host "  & `"$env:USERPROFILE\.claude\bin\Set-Proxy.ps1`"" -ForegroundColor Gray
Write-Host "Или через Пуск -> 'Claude (with proxy)' (одним кликом)." -ForegroundColor Gray
Write-Host ""
