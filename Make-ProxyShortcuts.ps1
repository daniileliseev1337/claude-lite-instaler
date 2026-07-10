<#
.SYNOPSIS
Создаёт на рабочем столе два ярлыка запуска через корпоративный прокси:
  - «Claude (прокси)»  -> Start-Claude.bat  (Set-Proxy с DPAPI-паролем + выбор CLI/VSCode/Desktop)
  - «Chrome (прокси)»  -> Start-Chrome-Proxy.bat (выделенный профиль, пароль запоминается)

Иконки — bin/icons/*.ico (лого приложения + бейдж-замок «прокси»).
Идемпотентно: повторный запуск перезаписывает ярлыки. Ничего не требует прав админа.
#>
$ErrorActionPreference = 'Stop'

$bin     = Join-Path $env:USERPROFILE '.claude\bin'
$icons   = Join-Path $bin 'icons'
$desktop = [Environment]::GetFolderPath('Desktop')
$ws = New-Object -ComObject WScript.Shell

function New-Lnk {
    param($Name, $Target, $Icon, $Desc)
    if (-not (Test-Path $Target)) { Write-Host "SKIP $Name — нет target: $Target" -ForegroundColor Yellow; return }
    $path = Join-Path $desktop $Name
    $s = $ws.CreateShortcut($path)
    $s.TargetPath       = $Target
    $s.WorkingDirectory = Split-Path $Target -Parent
    if (Test-Path $Icon) { $s.IconLocation = $Icon }
    $s.Description       = $Desc
    $s.Save()
    if (Test-Path $path) { Write-Host "OK   $Name" -ForegroundColor Green }
    else { Write-Host "FAIL $Name" -ForegroundColor Red }
}

New-Lnk -Name 'Claude (прокси).lnk' `
        -Target (Join-Path $bin 'Start-Claude.bat') `
        -Icon   (Join-Path $icons 'claude-proxy.ico') `
        -Desc   'Claude Code через корпоративный прокси. Пароль спросит один раз и запомнит (DPAPI).'

New-Lnk -Name 'Chrome (прокси).lnk' `
        -Target (Join-Path $bin 'Start-Chrome-Proxy.bat') `
        -Icon   (Join-Path $icons 'chrome-proxy.ico') `
        -Desc   'Google Chrome через корпоративный прокси. Выделенный профиль, пароль запоминается.'

Write-Host ""
Write-Host "Готово. Ярлыки на рабочем столе: $desktop" -ForegroundColor Cyan
