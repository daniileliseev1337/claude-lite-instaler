<#
.SYNOPSIS
Lite installer for Claude Code workstation: VS Code + extension + CLI +
proxy + uv + MCP servers + ~/.claude/ синхронизированный с claude-base.
No admin rights required.

.DESCRIPTION
Step-by-step orchestrator. Asks before each stage:

  1. Proxy           Set HTTP_PROXY / HTTPS_PROXY for current session.
  2. VS Code         User installer, silent, %LOCALAPPDATA%\Programs\.
  3. Claude Code CLI Official installer, %USERPROFILE%\.local\bin\.
  4. VS Code ext     anthropic.claude-code from Marketplace.
  5. uv              Python package manager (needed for uvx / MCP).
  6. MCP servers     8 user-scope servers via 'claude mcp add'.
  7. claude-base sync ~/.claude/ становится git-рабочей-копией claude-base
                     (CLAUDE.md, agents, skills, memory, sessions, harvested).

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
    -Title       "Stage 1/7: Proxy" `
    -Description "Required if you are behind a corporate Basic-auth proxy." `
    -Question    "Set HTTP proxy for the current session?" `
    -Script      "Set-Proxy.ps1"

Run-Stage `
    -Title       "Stage 2/7: VS Code (User installer)" `
    -Description "Installs VS Code into %LOCALAPPDATA%\Programs\, no admin." `
    -Question    "Install VS Code?" `
    -Script      "Install-VSCode.ps1"

Run-Stage `
    -Title       "Stage 3/7: Claude Code CLI" `
    -Description "Official Anthropic installer. Standalone ~250 MB binary." `
    -Question    "Install Claude Code CLI?" `
    -Script      "Install-ClaudeCode.ps1"

Run-Stage `
    -Title       "Stage 4/7: VS Code Claude extension" `
    -Description "Marketplace extension 'anthropic.claude-code'." `
    -Question    "Install Claude Code extension into VS Code?" `
    -Script      "Install-VSCodeExt.ps1"

Run-Stage `
    -Title       "Stage 5/7: uv (Python package manager)" `
    -Description "Provides 'uvx' to run the MCP servers." `
    -Question    "Install uv?" `
    -Script      "Install-UV.ps1"

Run-Stage `
    -Title       "Stage 6/7: MCP servers" `
    -Description "Adds 8 user-scope MCP servers via 'claude mcp add'." `
    -Question    "Add MCP servers?" `
    -Script      "Setup-MCP-Servers.ps1"

Run-Stage `
    -Title       "Stage 7/7: claude-base sync" `
    -Description "Makes ~/.claude/ a git working copy of claude-base (CLAUDE.md, agents, skills, memory, sessions, harvested). For existing non-git ~/.claude/ -- migration with backup, preserving credentials/history/plugins/projects." `
    -Question    "Sync ~/.claude/ with claude-base?" `
    -Script      "Apply-ClaudeMd.ps1" `
    -Args        @(if ($Yes) { '-Yes' } else { @() })

# === Done ===========================================================
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and re-open PowerShell so PATH picks up code/claude/uv." -ForegroundColor White
Write-Host "  2. Run 'claude auth login' (browser flow) to log in." -ForegroundColor White
Write-Host "  3. Restart Claude Code session to load MCP servers, skills, CLAUDE.md." -ForegroundColor White
Write-Host "  4. Verify with 'claude mcp list' (should show 8 servers)." -ForegroundColor White
Write-Host "  5. Open ~/.claude/CLAUDE.md and add personal rules in USER EXTENSIONS section." -ForegroundColor White
Write-Host "  6. Future updates: re-run this installer (it does a git pull)." -ForegroundColor White
Write-Host ""
Write-Host "Each new terminal needs proxy re-set:" -ForegroundColor White
Write-Host "  & '$here\Set-Proxy.ps1'" -ForegroundColor Gray
Write-Host ""
