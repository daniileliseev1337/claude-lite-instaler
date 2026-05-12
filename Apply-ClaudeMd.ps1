<#
.SYNOPSIS
Stage 7: synchronize ~/.claude/ with the claude-base git repository.

.DESCRIPTION
Ensures ~/.claude/ is a git working copy of claude-base, while preserving
the user's personal files (credentials, history, plugins, projects).

4 cases:

CASE 1 -- ~/.claude/ does not exist:
    git clone <BaseRepo> ~/.claude/

CASE 2 -- ~/.claude/.git exists AND origin matches claude-base:
    git pull --rebase --autostash

CASE 3 -- ~/.claude/.git exists but origin is NOT claude-base:
    error -- needs manual resolution (likely leftover from another install).

CASE 4 -- ~/.claude/ exists but is NOT a git repo:
    migration: backup -> preserve user files -> clone -> restore user files.
    Requires user confirmation (or -Yes flag).

.PARAMETER BaseRepo
URL of the claude-base git repository. Defaults to public daniileliseev1337 repo.

.PARAMETER Yes
Skip confirmation prompt for migration (CASE 4) -- for CI / non-interactive use.

.NOTES
Idempotent: re-running yields the same end state.
ASCII-only Write-Host messages to avoid Windows PowerShell 5.1 codepage issues.
#>

[CmdletBinding()]
param(
    [string]$BaseRepo = 'https://github.com/daniileliseev1337/claude-base.git',
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'

# User files / dirs that must survive migration (CASE 4).
# These are also ignored by claude-base whitelist .gitignore.
$PreservedItems = @(
    '.credentials.json',
    'settings.local.json',
    'history.jsonl',
    'file-history',
    'backups',
    'cache',
    'downloads',
    'plugins',
    'projects'
)

function Write-Step { param($m) Write-Host "  $m" -ForegroundColor Cyan }
function Write-OK   { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  [WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  [ERR] $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Stage 7: sync ~/.claude/ with claude-base ===" -ForegroundColor White
Write-Host "    Repo: $BaseRepo" -ForegroundColor Gray

# Check git is available
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Err "git is not in PATH. Install Git for Windows and re-run."
    exit 1
}

# === CASE 1: fresh install ===
if (-not (Test-Path $ClaudeDir)) {
    Write-Step "~/.claude/ does not exist -- cloning claude-base..."
    # Bypass HTTP_PROXY for git only: corp proxies often block CONNECT
    # while allowing HTTPS GET. Parent process keeps proxy for other tools.
    git -c http.proxy="" -c https.proxy="" clone $BaseRepo $ClaudeDir
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git clone failed. Check network/proxy."
        exit 1
    }
    Write-OK "claude-base cloned into $ClaudeDir"
    return
}

# === CASE 2 / 3: ~/.claude/.git exists ===
$GitDir = Join-Path $ClaudeDir '.git'
if (Test-Path $GitDir) {
    Push-Location $ClaudeDir
    try {
        $remote = & git config --get remote.origin.url 2>$null
        if (-not $remote) {
            Write-Err "~/.claude/.git exists but no origin remote configured."
            Write-Err "Resolve manually:"
            Write-Err "  git -C `"$ClaudeDir`" remote add origin $BaseRepo"
            Write-Err "  git -C `"$ClaudeDir`" fetch origin"
            Write-Err "  git -C `"$ClaudeDir`" reset --hard origin/main"
            exit 1
        }

        # Normalize: strip trailing slash and .git for comparison
        $expected = ($BaseRepo -replace '\.git$', '') -replace '/$',''
        $actual   = ($remote   -replace '\.git$', '') -replace '/$',''

        if ($actual -ne $expected) {
            # === CASE 3: foreign remote ===
            Write-Err "~/.claude/.git remote = $remote"
            Write-Err "expected:                $BaseRepo"
            Write-Err ""
            Write-Err "~/.claude/ is bound to a different git repo than expected."
            Write-Err "Possible causes: leftover from another install, manual change, typo in -BaseRepo."
            Write-Err ""
            Write-Err "If you want to switch to claude-base, resolve manually:"
            Write-Err "  Rename-Item `"$ClaudeDir`" `"$ClaudeDir.bak-<timestamp>`""
            Write-Err "  Re-run Install.ps1 (a fresh clone will happen)"
            exit 1
        }

        # === CASE 2: correct remote -- pull ===
        Write-Step "Remote matches claude-base. Pulling..."
        # Bypass HTTP_PROXY for git only (see CASE 1 comment).
        $pullOutput = & git -c http.proxy="" -c https.proxy="" pull --rebase --autostash 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-Err "git pull failed (exit=$LASTEXITCODE). git output:"
            Write-Host $pullOutput -ForegroundColor DarkGray
            if ($pullOutput -match 'Proxy CONNECT aborted|Could not resolve host|Failed to connect|unable to access') {
                Write-Err "Network/proxy error -- NOT a merge conflict."
                Write-Err "Check network access to GitHub or proxy configuration."
            } elseif ($pullOutput -match 'CONFLICT|merge conflict|could not apply') {
                Write-Err "Merge conflict (likely in the USER EXTENSIONS section of CLAUDE.md)."
                Write-Err "Open $ClaudeDir, resolve manually, then run 'git rebase --continue'."
            } else {
                Write-Err "See git output above. Resolve manually in $ClaudeDir."
            }
            exit 1
        }
        Write-OK "~/.claude/ updated from claude-base"
    } finally {
        Pop-Location
    }
    return
}

# === CASE 4: ~/.claude/ exists but is not a git repo ===
Write-Warn "~/.claude/ exists but is not a git repo. Migration needed."

if (-not $Yes) {
    Write-Host ""
    Write-Host "  The following actions will be performed:"
    Write-Host "    1. Full backup of ~/.claude/ -> ~/.claude.backup-<timestamp>/"
    Write-Host "    2. User personal files will be preserved (credentials, history,"
    Write-Host "       plugins, projects, file-history, backups, cache, downloads,"
    Write-Host "       settings.local.json):"
    foreach ($item in $PreservedItems) { Write-Host "         - $item" }
    Write-Host "    3. Current ~/.claude/ will be removed (full backup is in step 1)."
    Write-Host "    4. claude-base will be cloned into a fresh ~/.claude/."
    Write-Host "    5. Personal files from step 2 will be restored."
    Write-Host ""
    $confirm = Read-Host "  Proceed? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Warn "Cancelled by user."
        exit 0
    }
}

$timestamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir   = "$ClaudeDir.backup-$timestamp"
$preserveDir = Join-Path $env:TEMP "claude-preserve-$timestamp"

# Step 1: full backup
Write-Step "Backing up entire ~/.claude/ -> $backupDir..."
Copy-Item -Path $ClaudeDir -Destination $backupDir -Recurse -Force
Write-OK "Backup created"

# Step 2: move preserved items to temp
New-Item -ItemType Directory -Path $preserveDir -Force | Out-Null
foreach ($item in $PreservedItems) {
    $src = Join-Path $ClaudeDir $item
    if (Test-Path $src) {
        $dest = Join-Path $preserveDir $item
        Move-Item -Path $src -Destination $dest -Force
        Write-OK "preserve: $item"
    }
}

# Step 3: remove remaining ~/.claude/
Write-Step "Removing current ~/.claude/ (full backup exists)..."
Remove-Item -Path $ClaudeDir -Recurse -Force

# Step 4: clone claude-base
Write-Step "Cloning claude-base..."
# Bypass HTTP_PROXY for git only (see CASE 1 comment).
git -c http.proxy="" -c https.proxy="" clone $BaseRepo "$ClaudeDir"
if ($LASTEXITCODE -ne 0) {
    Write-Err "git clone failed. Restoring from backup..."
    # The backup is a FULL copy of the original ~/.claude/ taken BEFORE
    # preserve items were moved out. So backup already contains them.
    # Just move the backup back -- DO NOT re-apply preserved items
    # (would conflict because they are already in the restored backup).
    if (Test-Path $ClaudeDir) {
        # Partial state from failed clone -- remove before restoring
        Remove-Item -Path $ClaudeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item -Path $backupDir -Destination $ClaudeDir
    Remove-Item $preserveDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Warn "Restored from backup. Original ~/.claude/ is back in place."
    Write-Warn "Common cause: corporate proxy. Run Set-Proxy.ps1 first, or"
    Write-Warn "configure git global proxy: git config --global http.proxy ..."
    exit 1
}
Write-OK "claude-base cloned"

# Step 5: restore preserved items
foreach ($item in (Get-ChildItem $preserveDir)) {
    $dest = Join-Path $ClaudeDir $item.Name
    Move-Item -Path $item.FullName -Destination $dest -Force
    Write-OK "restored: $($item.Name)"
}
Remove-Item $preserveDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-OK "Migration complete."
Write-OK "Backup: $backupDir"
Write-Host "         (you can remove it after verifying everything works)"
