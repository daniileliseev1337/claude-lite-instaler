@echo off
REM Start-Claude.bat
REM Запускает PowerShell с обходом ExecutionPolicy и стартует Start-Claude.ps1.
REM -NoExit оставляет окно открытым после завершения claude (для повторных запусков).
REM
REM Двойной клик из File Explorer работает.

powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Claude.ps1" %*
