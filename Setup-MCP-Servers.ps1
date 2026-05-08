<#
.SYNOPSIS
Adds basic MCP servers to Claude Code via 'claude mcp add'.

.DESCRIPTION
Installs six Python-based MCP servers (V1+V2+V3) (via uvx, no Node.js needed):
- markitdown        - universal converter PDF/DOCX/XLSX/PPTX to Markdown
- document-loader   - office documents reader with slide-as-PNG support
- word              - direct DOCX manipulation (create/edit/format)

All servers are added at user scope (available across all projects).
Requires uv installed (run Install-UV.ps1 first).
#>

$ErrorActionPreference = "Continue"

# Refresh PATH
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = "$machinePath;$userPath"

# Check claude
$claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCheck) {
    Write-Host "claude (Claude Code CLI) not found in PATH" -ForegroundColor Red
    Write-Host "Make sure $env:USERPROFILE\.local\bin is in User PATH" -ForegroundColor Yellow
    exit 1
}

# Check uvx
$uvxCheck = Get-Command uvx -ErrorAction SilentlyContinue
if (-not $uvxCheck) {
    Write-Host "uvx not found in PATH" -ForegroundColor Red
    Write-Host "Run Install-UV.ps1 first, then close/reopen PowerShell." -ForegroundColor Yellow
    exit 1
}

# Check proxy
if (-not $env:HTTPS_PROXY) {
    Write-Host "WARNING: HTTPS_PROXY not set." -ForegroundColor Yellow
    Write-Host "MCP servers will be downloaded from PyPI on first use." -ForegroundColor Yellow
    Write-Host "If behind corporate proxy, set HTTPS_PROXY first." -ForegroundColor Yellow
    Write-Host ""
    $resp = Read-Host "Continue? (y/n)"
    if ($resp -ne "y") { exit 0 }
}

Write-Host "Adding MCP servers (user scope)..." -ForegroundColor Cyan
Write-Host ""

$servers = @(
    # === V1 (Волна 7) ===
    @{
        name = "markitdown"
        cmd = @("uvx", "markitdown-mcp")
        desc = "Universal document to Markdown converter (V1)"
    },
    @{
        name = "document-loader"
        cmd = @("uvx", "awslabs.document-loader-mcp-server@latest")
        desc = "Office documents reader with slide-as-PNG (V1)"
    },
    @{
        name = "word"
        cmd = @("uvx", "--from", "office-word-mcp-server", "word_mcp_server")
        desc = "Direct DOCX manipulation (V1)"
    },
    # === V2 (Волна 8) ===
    @{
        name = "excel"
        cmd = @("uvx", "excel-mcp-server", "stdio")
        desc = "XLSX manipulation via openpyxl (haris-musa/excel-mcp-server, V2)"
    },
    @{
        name = "pdf-mcp"
        cmd = @("uvx", "pdf-mcp")
        desc = "PDF reading with table extraction and caching (jztan/pdf-mcp, V2)"
    },
    # === V3 (Волна 8) ===
    @{
        name = "sequential-thinking"
        cmd = @("uvx", "sequential-thinking-mcp")
        desc = "Meta-cognition tool for complex multi-step problem-solving (V3, philogicae/sequential-thinking-mcp)"
    },
    # === Универсальные офисные ===
    @{
        name = "fetch"
        cmd = @("uvx", "mcp-server-fetch")
        desc = "Official Anthropic fetch server: download arbitrary URLs (HTML/text)"
    },
    @{
        name = "time"
        cmd = @("uvx", "mcp-server-time")
        desc = "Official Anthropic time server: current time, time zones, date math"
    }
)

$added = 0
$failed = @()

foreach ($srv in $servers) {
    Write-Host "Adding $($srv.name) - $($srv.desc)..." -NoNewline

    $args = @("mcp", "add", "--scope", "user", $srv.name, "--") + $srv.cmd

    $output = & claude @args 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
        $added++
    }
    else {
        if ($output -match "already exists" -or $output -match "already configured") {
            Write-Host " already added" -ForegroundColor Yellow
            $added++
        }
        else {
            Write-Host " FAILED" -ForegroundColor Red
            $failed += [PSCustomObject]@{
                Server = $srv.name
                Error = ($output | Out-String).Trim()
            }
        }
    }
}

Write-Host ""
Write-Host "Result: $added/$($servers.Count) servers added" -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors:" -ForegroundColor Red
    $failed | Format-List
}

Write-Host ""
Write-Host "Verify with: claude mcp list" -ForegroundColor Cyan
Write-Host "After installation, RESTART Claude Code session to load new servers." -ForegroundColor Yellow
