<#
.SYNOPSIS
Stage 8: синхронизация ~/.claude/ с git-репо claude-base.

.DESCRIPTION
Обеспечивает чтобы ~/.claude/ был git-рабочей-копией claude-base,
с сохранением личных файлов пользователя (credentials, history,
plugins, projects).

4 случая:

CASE 1 — ~/.claude/ не существует:
    git clone <BaseRepo> ~/.claude/

CASE 2 — ~/.claude/.git существует И origin совпадает с claude-base:
    git pull --rebase --autostash

CASE 3 — ~/.claude/.git существует, но origin НЕ claude-base:
    error — нужно решить вручную (вероятно, остатки старой установки).

CASE 4 — ~/.claude/ существует, но это не git-репо:
    миграция: backup → preserve user files → clone → restore user files.
    Требует подтверждения пользователя (или флаг -Yes).

.PARAMETER BaseRepo
URL git-репо claude-base. По умолчанию — публичный репо daniileliseev1337.

.PARAMETER Yes
Не спрашивать подтверждения для миграции (CASE 4) — для CI/non-interactive
режима.

.NOTES
Скрипт идемпотентен — повторный запуск приводит к тому же состоянию.
#>

[CmdletBinding()]
param(
    [string]$BaseRepo = 'https://github.com/daniileliseev1337/claude-base.git',
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'

# Файлы / директории, которые принадлежат пользователю и должны сохраниться
# при миграции. Все они также игнорируются через whitelist .gitignore
# в claude-base, так что после clone не будут конфликтовать с tracked-файлами.
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
function Write-OK   { param($m) Write-Host "  ✓ $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  ⚠ $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "  ✗ $m" -ForegroundColor Red }

Write-Host ""
Write-Host "=== Stage 8: sync ~/.claude/ with claude-base ===" -ForegroundColor White
Write-Host "    Repo: $BaseRepo" -ForegroundColor Gray

# Проверка что git доступен
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Err "git не найден в PATH. Установите git и перезапустите."
    exit 1
}

# === CASE 1: ~/.claude/ не существует — fresh install ===
if (-not (Test-Path $ClaudeDir)) {
    Write-Step "~/.claude/ не существует — клонирую claude-base..."
    git clone $BaseRepo $ClaudeDir
    if ($LASTEXITCODE -ne 0) {
        Write-Err "git clone завершился с ошибкой. Проверьте сеть/прокси."
        exit 1
    }
    Write-OK "claude-base склонирован в $ClaudeDir"
    return
}

# === CASE 2 / 3: ~/.claude/.git существует ===
$GitDir = Join-Path $ClaudeDir '.git'
if (Test-Path $GitDir) {
    Push-Location $ClaudeDir
    try {
        $remote = & git config --get remote.origin.url 2>$null
        if (-not $remote) {
            Write-Err "~/.claude/.git существует, но remote origin не настроен."
            Write-Err "Решите вручную:"
            Write-Err "  git -C `"$ClaudeDir`" remote add origin $BaseRepo"
            Write-Err "  git -C `"$ClaudeDir`" fetch origin"
            Write-Err "  git -C `"$ClaudeDir`" reset --hard origin/main"
            exit 1
        }

        # Нормализация: убираем trailing slash и .git для сравнения
        $expected = ($BaseRepo -replace '\.git$', '') -replace '/$',''
        $actual   = ($remote   -replace '\.git$', '') -replace '/$',''

        if ($actual -ne $expected) {
            # === CASE 3: чужой remote ===
            Write-Err "~/.claude/.git remote = $remote"
            Write-Err "ожидалось:                $BaseRepo"
            Write-Err ""
            Write-Err "~/.claude/ уже привязан к другому git-репо. Это неожиданное состояние."
            Write-Err "Возможные причины: остатки от другой установки, ручное вмешательство, опечатка в -BaseRepo."
            Write-Err ""
            Write-Err "Если хотите перейти на claude-base — решите вручную:"
            Write-Err "  Rename-Item `"$ClaudeDir`" `"$ClaudeDir.bak-<timestamp>`""
            Write-Err "  Перезапустите Install.ps1 (произойдёт fresh clone)"
            exit 1
        }

        # === CASE 2: правильный remote — pull ===
        Write-Step "Remote совпадает с claude-base. Pull..."
        git pull --rebase --autostash
        if ($LASTEXITCODE -ne 0) {
            Write-Err "git pull завершился с ошибкой."
            Write-Err "Возможный конфликт в USER EXTENSIONS секции CLAUDE.md."
            Write-Err "Откройте $ClaudeDir, разрешите конфликт вручную, выполните 'git rebase --continue'."
            exit 1
        }
        Write-OK "~/.claude/ обновлён из claude-base"
    } finally {
        Pop-Location
    }
    return
}

# === CASE 4: ~/.claude/ существует, но не git-репо ===
Write-Warn "~/.claude/ существует, но это не git-репо. Нужна миграция."

if (-not $Yes) {
    Write-Host ""
    Write-Host "  Будут выполнены следующие действия:"
    Write-Host "    1. Создан backup всей ~/.claude/ → ~/.claude.backup-<timestamp>/"
    Write-Host "    2. Личные файлы пользователя сохранятся (credentials, history,"
    Write-Host "       plugins, projects, file-history, backups, cache, downloads,"
    Write-Host "       settings.local.json):"
    foreach ($item in $PreservedItems) { Write-Host "         - $item" }
    Write-Host "    3. Текущая ~/.claude/ удалится (полный backup есть в шаге 1)."
    Write-Host "    4. Будет git clone claude-base в ~/.claude/."
    Write-Host "    5. Личные файлы из шага 2 вернутся в новую ~/.claude/."
    Write-Host ""
    $confirm = Read-Host "  Продолжить? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Warn "Отменено пользователем."
        exit 0
    }
}

$timestamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir   = "$ClaudeDir.backup-$timestamp"
$preserveDir = Join-Path $env:TEMP "claude-preserve-$timestamp"

# Step 1: full backup
Write-Step "Backup всей ~/.claude/ → $backupDir..."
Copy-Item -Path $ClaudeDir -Destination $backupDir -Recurse -Force
Write-OK "Backup создан"

# Step 2: вынести preserved items в temp
New-Item -ItemType Directory -Path $preserveDir -Force | Out-Null
foreach ($item in $PreservedItems) {
    $src = Join-Path $ClaudeDir $item
    if (Test-Path $src) {
        $dest = Join-Path $preserveDir $item
        Move-Item -Path $src -Destination $dest -Force
        Write-OK "preserve: $item"
    }
}

# Step 3: удалить остаток ~/.claude/
Write-Step "Удаляю текущую ~/.claude/ (есть полный backup)..."
Remove-Item -Path $ClaudeDir -Recurse -Force

# Step 4: clone claude-base
Write-Step "Clone claude-base..."
git clone $BaseRepo $ClaudeDir
if ($LASTEXITCODE -ne 0) {
    Write-Err "git clone не удался. Восстанавливаю из backup..."
    Move-Item -Path $backupDir -Destination $ClaudeDir
    foreach ($item in (Get-ChildItem $preserveDir -ErrorAction SilentlyContinue)) {
        Move-Item -Path $item.FullName -Destination (Join-Path $ClaudeDir $item.Name) -Force
    }
    Remove-Item $preserveDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-OK "claude-base склонирован"

# Step 5: вернуть preserved items
foreach ($item in (Get-ChildItem $preserveDir)) {
    $dest = Join-Path $ClaudeDir $item.Name
    Move-Item -Path $item.FullName -Destination $dest -Force
    Write-OK "restored: $($item.Name)"
}
Remove-Item $preserveDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-OK "Миграция завершена."
Write-OK "Backup: $backupDir"
Write-Host "         (можно удалить после проверки что всё работает)"
