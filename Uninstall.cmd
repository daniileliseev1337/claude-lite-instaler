@echo off
REM Wrapper: launch Uninstall.ps1 bypassing PowerShell ExecutionPolicy.
REM Double-clickable. Does not change system policy permanently
REM (-ExecutionPolicy Bypass is process-scoped to this PowerShell run).
REM No admin rights required.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Uninstall.ps1" %*

REM Keep the window open so user sees output if launched by double-click.
echo.
pause
