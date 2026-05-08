; Start-Claude.ahk — глобальная горячая клавиша Ctrl+Alt+C для запуска Claude.
; Требует AutoHotkey v2 (https://autohotkey.com, install for current user — без админ-прав).
;
; Как пользоваться:
;   1. Установить AutoHotkey v2 (один раз).
;   2. Двойной клик по этому файлу — скрипт запускается, в трее появится иконка
;      и уведомление "Hotkey Ctrl+Alt+C готов".
;   3. В любой момент Ctrl+Alt+C → откроется PowerShell с прокси и Claude.
;   4. Чтобы скрипт запускался при старте Windows — создать ярлык на этот файл
;      и положить в папку:
;        %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\
;      (Win+R → shell:startup → перетащить ярлык).

#Requires AutoHotkey v2.0
#SingleInstance Force

; A_ScriptDir = папка, где лежит этот .ahk. Так скрипт работает у любого
; пользователя без правок путей.
^!c::
{
    Run(A_ScriptDir . "\Start-Claude.bat")
}

TrayTip "Start-Claude.ahk", "Hotkey Ctrl+Alt+C готов", 1
