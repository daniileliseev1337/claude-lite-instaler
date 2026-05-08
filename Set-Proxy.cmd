@echo off
REM Wrapper: launch Set-Proxy.ps1 bypassing PowerShell ExecutionPolicy.
REM Double-clickable from File Explorer.
REM
REM -NoExit keeps the PowerShell window open after Set-Proxy.ps1 finishes,
REM so HTTPS_PROXY / HTTP_PROXY env-vars stay set in this session.
REM Continue working with claude / VS Code in the SAME window.
REM Closing the window clears the proxy.
REM
REM No admin rights required.

powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-Proxy.ps1" %*
