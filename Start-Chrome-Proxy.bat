@echo off
REM Start-Chrome-Proxy.bat
REM Запускает Chrome через корп-прокси (читает host:port из ~\.claude-proxy.json).
REM Подробности и параметры: Start-Chrome-Proxy.ps1 (-OwnProfile).
REM
REM Двойной клик из File Explorer работает.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Chrome-Proxy.ps1" %*
if errorlevel 1 pause
