<#
.SYNOPSIS
Запускает Google Chrome через корпоративный прокси (--proxy-server).

.DESCRIPTION
Читает host:port из "%USERPROFILE%\.claude-proxy.json" (создаётся Set-Proxy.ps1
при первой настройке). Если конфига нет — спрашивает host:port и сохраняет.
Логин/пароль прокси Chrome спросит сам (Basic-auth диалог при первом запросе).

GitHub-домены идут МИМО прокси (--proxy-bypass-list) — корп-прокси блокирует
CONNECT к github.com (см. memory/proxy_github.md).

ВАЖНО: если Chrome уже запущен, новый процесс присоединяется к существующему
и прокси-флаги НЕ применяются. Скрипт это детектит и предлагает выбор:
закрыть Chrome / открыть отдельный прокси-профиль / отмена.

Parameters:
  -OwnProfile  запустить с отдельным user-data-dir (основной Chrome не трогаем,
               но в этом окне не будет твоих закладок и сессий)
#>
param(
    [switch]$OwnProfile
)

$ErrorActionPreference = 'Stop'

# === host:port из конфига Set-Proxy.ps1 ============================
$configPath = Join-Path $env:USERPROFILE '.claude-proxy.json'
$hostPort = $null

if (Test-Path $configPath) {
    try {
        $hostPort = (Get-Content $configPath -Raw | ConvertFrom-Json).hostPort
    } catch {
        Write-Host "Конфиг $configPath повреждён, спрошу заново." -ForegroundColor Yellow
    }
}

if (-not $hostPort) {
    $hostPort = Read-Host "Proxy host:port (e.g. proxy.example.com:8080)"
    if ([string]::IsNullOrWhiteSpace($hostPort)) {
        Write-Host "Пустой host:port, выходим." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $configPath)) {
        @{ hostPort = $hostPort } | ConvertTo-Json | Set-Content -Path $configPath -Encoding utf8
        Write-Host "Сохранил host:port в $configPath" -ForegroundColor Gray
    }
}

# === Найти chrome.exe ===============================================
$chrome = $null
foreach ($key in @(
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe')) {
    if (-not $chrome -and (Test-Path $key)) {
        $chrome = (Get-ItemProperty $key).'(default)'
    }
}
if (-not $chrome) {
    foreach ($candidate in @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")) {
        if (Test-Path $candidate) { $chrome = $candidate; break }
    }
}
if (-not $chrome -or -not (Test-Path $chrome)) {
    Write-Host "Chrome не найден (App Paths и стандартные папки пусты)." -ForegroundColor Red
    exit 1
}

# === Chrome уже запущен? Флаги не применятся ========================
$running = Get-Process chrome -ErrorAction SilentlyContinue
if ($running -and -not $OwnProfile) {
    Write-Host ""
    Write-Host "Chrome уже запущен — прокси-флаги НЕ применятся к работающему процессу." -ForegroundColor Yellow
    Write-Host "  [1] Я сам закрою Chrome, потом продолжить"
    Write-Host "  [2] Открыть отдельный прокси-профиль (без закладок основного)"
    Write-Host "  [3] Отмена"
    $choice = Read-Host "Выбор (1/2/3)"
    switch ($choice) {
        '1' {
            Read-Host "Закрой все окна Chrome и нажми Enter"
            if (Get-Process chrome -ErrorAction SilentlyContinue) {
                Write-Host "Chrome всё ещё запущен — выходим без запуска." -ForegroundColor Red
                exit 1
            }
        }
        '2' { $OwnProfile = $true }
        default { Write-Host "Отмена."; exit 0 }
    }
}

# === Запуск =========================================================
$chromeArgs = @(
    "--proxy-server=http://$hostPort",
    '--proxy-bypass-list=github.com;*.github.com;*.githubusercontent.com;<local>'
)
if ($OwnProfile) {
    $chromeArgs += "--user-data-dir=$env:LOCALAPPDATA\Google\ChromeProxyProfile"
}

Start-Process -FilePath $chrome -ArgumentList $chromeArgs
Write-Host ""
Write-Host "Chrome запущен через прокси http://$hostPort" -ForegroundColor Green
Write-Host "Логин/пароль прокси браузер спросит сам при первом запросе." -ForegroundColor Gray
if ($OwnProfile) {
    Write-Host "Профиль: отдельный (ChromeProxyProfile)." -ForegroundColor Gray
}
exit 0
