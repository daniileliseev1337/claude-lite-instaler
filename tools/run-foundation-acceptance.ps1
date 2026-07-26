[CmdletBinding()]
param(
  [AllowNull()][string]$PackageRoot = $null,
  [string[]]$SecretSignatures = @(
    'SECRET_ACCEPTANCE_CONFIG_71f4',
    'SECRET_ACCEPTANCE_ENV_38b9'
  )
)

$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceRoot = Join-Path $RepoRoot 'src\foundation'
Get-ChildItem -LiteralPath $SourceRoot -Filter '*.ps1' -File |
  Sort-Object Name |
  ForEach-Object { . $_.FullName }
. (Join-Path $RepoRoot 'tests\TestSupport.ps1')

function ConvertTo-AcceptanceStatus {
  param([bool]$Passed)
  if ($Passed) { return 'PASS' }
  return 'FAIL'
}

function Invoke-AcceptanceShellSuite {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [switch]$WindowsPowerShell
  )
  $Command = Get-Command $Executable -ErrorAction SilentlyContinue
  if ($null -eq $Command) {
    [IO.File]::WriteAllText($LogPath, 'shell unavailable')
    return [pscustomobject]@{ exit_code = 127; version = 'NOT_AVAILABLE' }
  }
  if ($WindowsPowerShell) {
    $Version = & $Executable -NoProfile -ExecutionPolicy Bypass -Command `
      '$PSVersionTable.PSVersion.ToString()' 2>$null
    & $Executable -NoProfile -ExecutionPolicy Bypass -File `
      (Join-Path $RepoRoot 'tests\run-tests.ps1') *> $LogPath
  } else {
    $Version = & $Executable -NoProfile -Command `
      '$PSVersionTable.PSVersion.ToString()' 2>$null
    & $Executable -NoProfile -File `
      (Join-Path $RepoRoot 'tests\run-tests.ps1') *> $LogPath
  }
  return [pscustomobject]@{
    exit_code = [int]$LASTEXITCODE
    version = [string](@($Version)[0])
  }
}

function Test-AcceptanceLogNames {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string[]]$Names
  )
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $Text = [IO.File]::ReadAllText($Path)
  foreach ($Name in $Names) {
    if (-not $Text.Contains("PASS $Name")) { return $false }
  }
  return $true
}

function Test-AcceptanceBytesContain {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Haystack,
    [Parameter(Mandatory = $true)][byte[]]$Needle
  )
  if ($Needle.Length -eq 0 -or $Haystack.Length -lt $Needle.Length) {
    return $false
  }
  for ($Offset = 0; $Offset -le $Haystack.Length - $Needle.Length; $Offset++) {
    $Match = $true
    for ($Index = 0; $Index -lt $Needle.Length; $Index++) {
      if ($Haystack[$Offset + $Index] -ne $Needle[$Index]) {
        $Match = $false
        break
      }
    }
    if ($Match) { return $true }
  }
  return $false
}

function Test-AcceptanceSecretScan {
  param(
    [Parameter(Mandatory = $true)][string[]]$Paths,
    [Parameter(Mandatory = $true)][string[]]$Signatures
  )
  $Files = @()
  foreach ($Path in $Paths) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      $Files += Get-Item -LiteralPath $Path -Force
    } elseif (Test-Path -LiteralPath $Path -PathType Container) {
      $Files += Get-ChildItem -LiteralPath $Path -Recurse -File -Force
    } else {
      return $false
    }
  }
  foreach ($File in $Files) {
    $Bytes = [IO.File]::ReadAllBytes($File.FullName)
    foreach ($Signature in $Signatures) {
      $Needle = [Text.UTF8Encoding]::new($false).GetBytes($Signature)
      if (Test-AcceptanceBytesContain $Bytes $Needle) { return $false }
    }
  }
  return $true
}

$RepoStatus = @(
  & git -C $RepoRoot status --porcelain=v1 --untracked-files=all 2>$null
)
if ($LASTEXITCODE -ne 0) {
  Throw-FoundationError -Code 'ACCEPTANCE_GIT_STATE_UNKNOWN' `
    -Message 'Acceptance requires a readable Git worktree'
}
if ($RepoStatus.Count -ne 0) {
  Throw-FoundationError -Code 'DIRTY_ACCEPTANCE_REPO' `
    -Message 'Acceptance requires a clean committed worktree'
}
$RepoCommit = [string](
  & git -C $RepoRoot rev-parse HEAD 2>$null | Select-Object -First 1
)
$RepoTree = [string](
  & git -C $RepoRoot rev-parse 'HEAD^{tree}' 2>$null |
    Select-Object -First 1
)
if (
  $RepoCommit -notmatch '^[0-9a-f]{40}$' -or
  $RepoTree -notmatch '^[0-9a-f]{40}$'
) {
  Throw-FoundationError -Code 'ACCEPTANCE_GIT_STATE_UNKNOWN' `
    -Message 'Acceptance requires one committed Git tree'
}

$AcceptanceBase = Join-Path $RepoRoot '.work\acceptance'
New-FoundationSafeDirectory $AcceptanceBase
$AttemptId = New-FoundationRandomId
$AttemptRoot = Join-Path $AcceptanceBase $AttemptId
New-FoundationSafeDirectory $AttemptRoot

$Ps7Log = Join-Path $AttemptRoot 'ps7-tests.log'
$Ps51Log = Join-Path $AttemptRoot 'ps51-tests.log'
$Ps7 = Invoke-AcceptanceShellSuite 'pwsh' $Ps7Log
$Ps51 = Invoke-AcceptanceShellSuite 'powershell.exe' $Ps51Log `
  -WindowsPowerShell
$Ps7Pass = $Ps7.exit_code -eq 0
$Ps51Pass = $Ps51.exit_code -eq 0

$SecurityNames = @(
  'rejects a reparse point in a managed destination ancestor during plan',
  'rejects a directory junction anywhere inside a package',
  'rejects a package payload hash mismatch',
  'rejects a stale package before opening a transaction',
  'rejects a stale destination before opening a transaction',
  'blocks plan and doctor when a pending journal exists',
  'rejects a malicious quarantine payload path',
  'rejects a dependency cycle in the acceptance inventory',
  'does not export seeded config or environment secrets',
  'bundles without network or external-process commands',
  'ships a bounded dual-shell synthetic acceptance runner'
)
$E2ENames = @(
  'completes the full fake-home install upgrade drift and rollback lifecycle',
  'recovers every exposed transaction failure point without unexplained change'
)
$SecurityLogsPass = (
  (Test-AcceptanceLogNames $Ps7Log $SecurityNames) -and
  (Test-AcceptanceLogNames $Ps51Log $SecurityNames)
)
$E2ELogsPass = (
  (Test-AcceptanceLogNames $Ps7Log $E2ENames) -and
  (Test-AcceptanceLogNames $Ps51Log $E2ENames)
)

$BundlePass = $false
$PackagePass = $false
$PayloadPass = $false
$SecretPass = $false
$FailureCode = $null
$BundleSha = $null
$ManifestSha = $null
$DoctorReportSha = $null
$ReleaseId = $null
$EffectivePackageRoot = $null

try {
  $BundleA = Join-Path $AttemptRoot 'bundle-a.ps1'
  $BundleB = Join-Path $AttemptRoot 'bundle-b.ps1'
  $null = & (Join-Path $RepoRoot 'tools\bundle-installer.ps1') `
    -OutputPath $BundleA
  $null = & (Join-Path $RepoRoot 'tools\bundle-installer.ps1') `
    -OutputPath $BundleB
  $BundleSha = Get-Sha256Lower $BundleA
  $BundlePass = $BundleSha -ceq (Get-Sha256Lower $BundleB)

  if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $SyntheticSource = Join-Path $AttemptRoot 'approved-source'
    Copy-Item -LiteralPath (
      Join-Path $RepoRoot 'tests\fixtures\approved-source'
    ) -Destination $SyntheticSource -Recurse
    [IO.File]::Copy(
      $BundleA,
      (Join-Path $SyntheticSource '_package\install.ps1'),
      $true
    )
    [IO.File]::Copy(
      (Join-Path $RepoRoot 'contracts\foundation\release-manifest.schema.json'),
      (Join-Path $SyntheticSource '_package\release-manifest.schema.json'),
      $true
    )
    $InventoryPath = Join-Path $AttemptRoot 'acceptance-inventory.json'
    Write-TestJson (
      New-TestAcceptanceInventory $SyntheticSource 'foundation-synthetic-0001'
    ) $InventoryPath
    $EffectivePackageRoot = Join-Path $AttemptRoot 'package'
    $null = New-FoundationPackage $SyntheticSource $InventoryPath `
      $EffectivePackageRoot
  } else {
    $EffectivePackageRoot = [IO.Path]::GetFullPath($PackageRoot)
  }

  $Manifest = Read-FoundationManifest (
    Join-Path $EffectivePackageRoot 'release-manifest.json'
  )
  $Verification = Test-FoundationPackage $EffectivePackageRoot $Manifest
  $PackagePass = [bool]$Verification.valid
  $ManifestSha = $Verification.manifest_sha256
  $ReleaseId = $Manifest.release_id

  $FakeUser = Join-Path $AttemptRoot 'fake-user'
  $FakeLocal = Join-Path $AttemptRoot 'fake-local'
  [IO.Directory]::CreateDirectory($FakeUser) | Out-Null
  [IO.Directory]::CreateDirectory($FakeLocal) | Out-Null
  [IO.File]::WriteAllText(
    (Join-Path $FakeUser 'config.toml'),
    "token=$($SecretSignatures[0])"
  )
  $InjectedEnvironment = [pscustomobject][ordered]@{
    windows = [string]@($Manifest.compatibility.windows)[0]
    powershell = [string]@($Manifest.compatibility.powershell)[0]
    target = [string]$Manifest.target
    install_role = [string]$Manifest.sync_policy.default_role
    client_version = [string]@($Manifest.compatibility.client_versions)[0]
    client_detected = $true
  }
  $InjectedEnvironment | Add-Member -NotePropertyName secret_token `
    -NotePropertyValue $SecretSignatures[1]
  $Plan = New-FoundationPlan $EffectivePackageRoot $FakeUser $FakeLocal `
    $InjectedEnvironment
  if ($Plan.blocked) {
    Throw-FoundationError -Code ([string]$Plan.blockers[0].code) `
      -Message 'Acceptance payload plan is blocked'
  }
  $Install = Invoke-FoundationInstall $Plan
  $DoctorReport = Join-Path $AttemptRoot 'doctor-safe.json'
  $Doctor = Invoke-FoundationDoctor $FakeUser $FakeLocal $DoctorReport `
    $InjectedEnvironment
  $Inventory = Invoke-FoundationInventory $EffectivePackageRoot `
    $FakeUser $FakeLocal
  $ActiveCount = @(
    $Manifest.components | Where-Object activation -CEQ 'ACTIVE_ELIGIBLE'
  ).Count
  $PayloadPass = (
    $ActiveCount -gt 0 -and
    $Doctor.healthy -and
    $Doctor.release_id -ceq $Manifest.release_id -and
    @($Inventory.components | Where-Object {
        $_.activation -CEQ 'ACTIVE_ELIGIBLE' -and $_.health -CNE 'HEALTHY'
      }).Count -eq 0
  )
  $DoctorReportSha = Get-Sha256Lower $DoctorReport
  $SecretPass = Test-AcceptanceSecretScan @(
    $EffectivePackageRoot,
    $DoctorReport
  ) $SecretSignatures
  if ($Install.installed) {
    $null = Invoke-FoundationRollback $FakeUser $FakeLocal $Manifest.target
  }
} catch {
  $FailureCode = [string]$_.Exception.Data['FoundationCode']
  if ([string]::IsNullOrWhiteSpace($FailureCode)) {
    $FailureCode = 'UNEXPECTED_FAILURE'
  }
}

$SecurityPass = $Ps7Pass -and $Ps51Pass -and $SecurityLogsPass -and $PackagePass
$E2EPass = $Ps7Pass -and $Ps51Pass -and $E2ELogsPass -and $PayloadPass
$FoundationPass = (
  $Ps7Pass -and $Ps51Pass -and $BundlePass -and
  $SecurityPass -and $E2EPass -and $SecretPass
)
$Result = [pscustomobject][ordered]@{
  schema_version = 1
  kind = 'foundation_synthetic_acceptance_safe'
  attempt_id = $AttemptId
  generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  repo_commit = $RepoCommit
  repo_tree = $RepoTree
  repo_worktree_clean = $true
  release_id = $ReleaseId
  shells = [pscustomobject][ordered]@{
    ps7 = $Ps7.version
    ps51 = $Ps51.version
  }
  hashes = [pscustomobject][ordered]@{
    bundle_sha256 = $BundleSha
    manifest_sha256 = $ManifestSha
    doctor_report_sha256 = $DoctorReportSha
  }
  checks = [pscustomobject][ordered]@{
    ps7 = ConvertTo-AcceptanceStatus $Ps7Pass
    ps51 = ConvertTo-AcceptanceStatus $Ps51Pass
    bundle_determinism = ConvertTo-AcceptanceStatus $BundlePass
    security_matrix = ConvertTo-AcceptanceStatus $SecurityPass
    e2e = ConvertTo-AcceptanceStatus $E2EPass
    secret_scan = ConvertTo-AcceptanceStatus $SecretPass
  }
  failure_code = $FailureCode
  foundation_synthetic = ConvertTo-AcceptanceStatus $FoundationPass
  full_release = 'NOT_PASS'
}
$ResultPath = Join-Path $AttemptRoot 'synthetic-acceptance-safe.json'
Write-CanonicalFoundationJsonExclusive $Result $ResultPath

Write-Output "PS7: $(ConvertTo-AcceptanceStatus $Ps7Pass)"
Write-Output "PS5.1: $(ConvertTo-AcceptanceStatus $Ps51Pass)"
Write-Output "BUNDLE_DETERMINISM: $(ConvertTo-AcceptanceStatus $BundlePass)"
Write-Output "SECURITY_MATRIX: $(ConvertTo-AcceptanceStatus $SecurityPass)"
Write-Output "E2E: $(ConvertTo-AcceptanceStatus $E2EPass)"
Write-Output "SECRET_SCAN: $(ConvertTo-AcceptanceStatus $SecretPass)"
Write-Output "FOUNDATION_SYNTHETIC: $(ConvertTo-AcceptanceStatus $FoundationPass)"
Write-Output 'FULL_RELEASE: NOT_PASS'
if (-not $FoundationPass) { exit 1 }
