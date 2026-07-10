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

# === Постоянный прокси-профиль (всегда) =============================
# Запускаем в ВЫДЕЛЕННОМ user-data-dir. Зачем:
#   - не конфликтует с основным Chrome: отдельный процесс, --proxy-server
#     применяется, даже если обычный Chrome уже открыт (не нужно его закрывать);
#   - Chrome ЗАПОМИНАЕТ логин/пароль прокси (Basic-auth) в этом профиле —
#     ввести ОДИН раз в попапе, дальше не спрашивает. Это и есть «пароль один раз».
$profileDir = Join-Path $env:LOCALAPPDATA 'Google\ChromeProxyProfile'

# === Запуск =========================================================
$chromeArgs = @(
    "--proxy-server=http://$hostPort",
    '--proxy-bypass-list=github.com;*.github.com;*.githubusercontent.com;<local>',
    "--user-data-dir=$profileDir"
)

Start-Process -FilePath $chrome -ArgumentList $chromeArgs
Write-Host ""
Write-Host "Chrome запущен через прокси http://$hostPort" -ForegroundColor Green
Write-Host "Профиль: выделенный ChromeProxyProfile (отдельно от основного Chrome)." -ForegroundColor Gray
Write-Host "Логин/пароль прокси Chrome спросит ОДИН раз и запомнит в этом профиле." -ForegroundColor Gray
exit 0
