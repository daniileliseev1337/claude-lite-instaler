<#
.SYNOPSIS
Sets HTTP_PROXY / HTTPS_PROXY for the current PowerShell session.

.DESCRIPTION
Interactive helper for corporate Basic-auth proxy. No hardcoded values.

First run:
  - asks for proxy "host:port", username, password
  - URL-encodes the password
  - sets $env:HTTPS_PROXY and $env:HTTP_PROXY for the current session
  - saves host:port and username to "%USERPROFILE%\.claude-proxy.json"
    (NOT the password)

Subsequent runs:
  - reads host:port and username from "%USERPROFILE%\.claude-proxy.json"
  - asks ONLY for the password

Parameters:
  -Reset  delete saved config and ask everything again
  -Off    remove HTTPS_PROXY / HTTP_PROXY from the current session
  -NoSave do not write config to disk on first run

Limitations:
  Works only with Basic-authentication proxies. For NTLM use a wrapper
  like Cntlm; for Negotiate / Kerberos this script will not help.

Scope:
  Affects only the current PowerShell session and its child processes
  (e.g. claude code launched from this terminal). Nothing is written to
  the registry or to user environment variables.
#>

param(
    [switch]$Off,
    [switch]$Reset,
    [switch]$ResetPassword,
    [switch]$NoSave
)

$ErrorActionPreference = "Stop"

$configPath = Join-Path $env:USERPROFILE ".claude-proxy.json"
# Пароль хранится зашифрованным через DPAPI (ConvertFrom-SecureString без -Key):
# расшифровать может ТОЛЬКО этот Windows-пользователь на ЭТОЙ машине. В открытом
# виде на диск НЕ ложится. Ввести один раз -> дальше запуски без вопроса.
$credPath   = Join-Path $env:USERPROFILE ".claude-proxy.cred"

# === -Off: clear and exit ============================================
if ($Off) {
    Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
    Remove-Item Env:HTTP_PROXY  -ErrorAction SilentlyContinue
    [System.Net.WebRequest]::DefaultWebProxy = $null
    Write-Host "Proxy cleared from current session." -ForegroundColor Green
    return
}

# === -Reset: drop saved config ======================================
if ($Reset) {
    if (Test-Path $configPath) {
        Remove-Item $configPath -Force
        Write-Host "Saved proxy config removed: $configPath" -ForegroundColor Yellow
    }
    if (Test-Path $credPath) {
        Remove-Item $credPath -Force
        Write-Host "Saved password removed: $credPath" -ForegroundColor Yellow
    }
}

# === -ResetPassword: drop only the saved password ===================
if ($ResetPassword -and (Test-Path $credPath)) {
    Remove-Item $credPath -Force
    Write-Host "Saved password removed (will ask once): $credPath" -ForegroundColor Yellow
}

# === Load or ask host:port + username ===============================
$hostPort = $null
$user     = $null

if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        $hostPort = $cfg.hostPort
        $user     = $cfg.user
        Write-Host "Loaded config: $hostPort (user: $user)" -ForegroundColor Gray
    }
    catch {
        Write-Host "Config file is broken, asking again." -ForegroundColor Yellow
        $hostPort = $null
        $user     = $null
    }
}

if (-not $hostPort) {
    $hostPort = Read-Host "Proxy host:port (e.g. proxy.example.com:8080)"
    if ([string]::IsNullOrWhiteSpace($hostPort)) {
        Write-Host "Empty host:port, aborting." -ForegroundColor Red
        exit 1
    }
}

if (-not $user) {
    $user = Read-Host "Proxy username"
    if ([string]::IsNullOrWhiteSpace($user)) {
        Write-Host "Empty username, aborting." -ForegroundColor Red
        exit 1
    }
}

# === Password: load from DPAPI store, or ask once =================
# Приоритет: сохранённый DPAPI-пароль -> иначе спросить inline (без popup).
$securePass  = $null
$pwFromStore = $false
if ((Test-Path $credPath) -and -not $ResetPassword) {
    try {
        $securePass  = (Get-Content $credPath -Raw).Trim() | ConvertTo-SecureString -ErrorAction Stop
        $pwFromStore = $true
        Write-Host "Password loaded from encrypted store (DPAPI)." -ForegroundColor Gray
    }
    catch {
        Write-Host "Saved password can't be decrypted (different user/machine?). Asking again." -ForegroundColor Yellow
        $securePass = $null
    }
}
if (-not $securePass) {
    $securePass = Read-Host "Proxy password for $user@$hostPort" -AsSecureString
}
if (-not $securePass -or $securePass.Length -eq 0) {
    Write-Host "Empty password, aborting." -ForegroundColor Red
    exit 1
}

$pw = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePass))
$pwEncoded = [uri]::EscapeDataString($pw)

$proxyUrl = "http://${user}:${pwEncoded}@${hostPort}"

$env:HTTPS_PROXY = $proxyUrl
$env:HTTP_PROXY  = $proxyUrl

# .NET WebRequest (used by Invoke-WebRequest / Invoke-RestMethod) does
# NOT reliably parse credentials from a "http://user:pass@host:port" URL
# under PowerShell 5.1 / .NET Framework. Set DefaultWebProxy with an
# explicit NetworkCredential so PS-native HTTP calls authenticate.
$webProxy = New-Object System.Net.WebProxy("http://${hostPort}", $true)
$webProxy.Credentials = New-Object System.Net.NetworkCredential($user, $pw)
[System.Net.WebRequest]::DefaultWebProxy = $webProxy

# Clear plaintext password from memory after use.
# $securePass намеренно НЕ обнуляем здесь — нужен ниже для сохранения в DPAPI-store.
$pw = $null
$pwEncoded = $null
[System.GC]::Collect()

# флаг для решения «сохранять ли пароль» (не сохраняем при 407 Proxy Auth)
$proxyAuthFailed = $false

Write-Host ""
Write-Host "Proxy set for current session: $hostPort (user: $user)" -ForegroundColor Green
Write-Host "[v2] env-vars + .NET DefaultWebProxy with NetworkCredential" -ForegroundColor Gray
Write-Host "Effective only in this terminal and its child processes." -ForegroundColor Yellow

# === Live smoke: actually try to authenticate against the proxy ====
Write-Host ""
Write-Host "Smoke test: HTTPS request through proxy ..." -ForegroundColor Cyan -NoNewline
try {
    $smoke = Invoke-WebRequest -Uri "https://www.microsoft.com/robots.txt" `
        -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 5 -ErrorAction Stop
    if ($smoke.StatusCode -eq 200) {
        Write-Host " OK (HTTP 200)" -ForegroundColor Green
    }
    else {
        Write-Host " unexpected HTTP $($smoke.StatusCode)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match '407') { $proxyAuthFailed = $true }
    Write-Host ""
    Write-Host "  If error is 407 'Proxy Authentication Required':" -ForegroundColor Yellow
    Write-Host "    - wrong username or password (re-run: .\Set-Proxy.ps1 -ResetPassword)" -ForegroundColor Yellow
    Write-Host "    - proxy uses NTLM or Negotiate, not Basic (this script supports only Basic)" -ForegroundColor Yellow
    Write-Host "  Stages 2/3/5 will fail until proxy auth works. Continue at your own risk." -ForegroundColor Yellow
}

# === Save host:port + username (no password) =======================
if (-not $NoSave -and -not (Test-Path $configPath)) {
    $cfg = @{
        hostPort = $hostPort
        user     = $user
    } | ConvertTo-Json

    Set-Content -Path $configPath -Value $cfg -Encoding utf8
    Write-Host "Saved host and user to: $configPath (no password)" -ForegroundColor Gray
}

# === Save password encrypted (DPAPI) — once, if newly entered =======
# Только если пароль был ВВЕДЁН в этот раз (не взят из store) и auth не упал (407).
if (-not $pwFromStore -and -not $NoSave) {
    if ($proxyAuthFailed) {
        Write-Host "Proxy auth failed (407) - password NOT saved. Re-run and enter the correct one." -ForegroundColor Yellow
    }
    else {
        try {
            # hex-шифр DPAPI — чистый ASCII; НЕ utf8 (BOM ломает обратное ConvertTo-SecureString)
            $securePass | ConvertFrom-SecureString | Set-Content -Path $credPath -Encoding ASCII
            Write-Host "Password saved encrypted (DPAPI): $credPath" -ForegroundColor Green
            Write-Host "Next launches won't ask for it. Change proxy pass -> Set-Proxy.ps1 -ResetPassword" -ForegroundColor Gray
        }
        catch {
            Write-Host "Could not save encrypted password: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
$securePass = $null
[System.GC]::Collect()

# === Quick check ====================================================
Write-Host ""
Write-Host "Quick checks:" -ForegroundColor Cyan

$claudeCheck = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCheck) {
    Write-Host "  claude: OK" -ForegroundColor Green
} else {
    Write-Host "  claude: NOT FOUND in PATH" -ForegroundColor Yellow
}

$uvxCheck = Get-Command uvx -ErrorAction SilentlyContinue
if ($uvxCheck) {
    Write-Host "  uvx:    OK" -ForegroundColor Green
} else {
    Write-Host "  uvx:    NOT FOUND (run Install-UV.ps1 first)" -ForegroundColor Yellow
}
