function New-FoundationRandomId {
  $Bytes = New-Object byte[] 32
  $Generator = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $Generator.GetBytes($Bytes) } finally { $Generator.Dispose() }
  return -join ($Bytes | ForEach-Object { $_.ToString('x2') })
}

function Get-FoundationStateRoot {
  param([Parameter(Mandatory = $true)][string]$LocalAppData)
  $Base = [IO.Path]::GetFullPath($LocalAppData)
  $Root = [IO.Path]::GetFullPath((Join-Path $Base 'LLMBase\codex-foundation'))
  if (-not $Root.StartsWith(
      $Base + [IO.Path]::DirectorySeparatorChar,
      [StringComparison]::OrdinalIgnoreCase)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'State root escaped LocalAppData'
  }
  return $Root
}

function Initialize-FoundationStateRoot {
  param([string]$LocalAppData)
  $LocalRoot = [IO.Path]::GetFullPath($LocalAppData)
  Assert-SafeExistingDirectory $LocalRoot
  $StateRoot = Get-FoundationStateRoot $LocalRoot
  New-FoundationSafeDirectory $StateRoot
  foreach ($Name in @('releases', 'backups', 'recovery', 'reports')) {
    New-FoundationSafeDirectory (Join-Path $StateRoot $Name)
  }
  return $StateRoot
}

function Test-PendingFoundationJournal {
  param([Parameter(Mandatory = $true)][string]$LocalAppData)
  return Test-Path -LiteralPath (
    Join-Path (Get-FoundationStateRoot $LocalAppData) 'transaction-journal.json'
  ) -PathType Leaf
}

function Read-FoundationActiveState {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [switch]$AllowMissing
  )
  $Path = Join-Path (Get-FoundationStateRoot $LocalAppData) 'state.json'
  if (-not (Test-Path -LiteralPath $Path)) {
    if ($AllowMissing) { return $null }
    Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Foundation state is not installed'
  }
  $State = Read-JsonFileStrict $Path 8388608
  Assert-ExactProperties $State @(
    'schema_version', 'release_id', 'manifest_sha256', 'compatibility',
    'active_components', 'active_files', 'quarantine_components',
    'rollback_snapshot_id', 'installed_at_utc'
  ) 'active state'
  if ($State.schema_version -ne 1 -or
      $State.release_id -notmatch '^foundation-[a-z0-9][a-z0-9.-]{0,79}$' -or
      $State.manifest_sha256 -notmatch '^[0-9a-f]{64}$' -or
      $State.rollback_snapshot_id -notmatch '^[0-9a-f]{64}$') {
    Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Active state identity is invalid'
  }
  Assert-ExactProperties $State.compatibility @('windows', 'powershell', 'codex_versions') 'state compatibility'
  $ComponentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  foreach ($Component in @($State.active_components)) {
    Assert-ExactProperties $Component @(
      'component_id', 'component_type', 'destination_relative_path', 'sha256', 'bytes'
    ) 'state component'
    if (-not $ComponentIds.Add([string]$Component.component_id) -or
        @('core', 'agent', 'skill') -cnotcontains [string]$Component.component_type -or
        $Component.sha256 -notmatch '^[0-9a-f]{64}$') {
      Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Invalid state component'
    }
  }
  $Destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($File in @($State.active_files)) {
    Assert-ExactProperties $File @(
      'component_id', 'path_id', 'destination_relative_path', 'sha256', 'bytes'
    ) 'state file'
    if (-not $ComponentIds.Contains([string]$File.component_id) -or
        -not $Destinations.Add([string]$File.destination_relative_path) -or
        $File.sha256 -notmatch '^[0-9a-f]{64}$') {
      Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Invalid state file'
    }
  }
  foreach ($Component in @($State.quarantine_components)) {
    Assert-ExactProperties $Component @(
      'component_id', 'component_type', 'activation', 'quarantine_reason',
      'sha256', 'evidence_ids'
    ) 'state quarantine component'
  }
  return $State
}

function Read-FoundationJournal {
  param([string]$LocalAppData)
  $Path = Join-Path (Get-FoundationStateRoot $LocalAppData) 'transaction-journal.json'
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Transaction journal is missing'
  }
  $Journal = Read-JsonFileStrict $Path 4194304
  Assert-ExactProperties $Journal @(
    'schema_version', 'kind', 'transaction_id', 'release_id', 'status',
    'next_step', 'snapshot_id', 'plan_fingerprint', 'created_paths',
    'updated_paths', 'created_directories', 'created_at_utc'
  ) 'transaction journal'
  if ($Journal.schema_version -ne 1 -or $Journal.status -cne 'OPEN' -or
      $Journal.transaction_id -notmatch '^[0-9a-f]{64}$' -or
      $Journal.snapshot_id -notmatch '^[0-9a-f]{64}$') {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Transaction journal is invalid'
  }
  return $Journal
}

function Invoke-FoundationAtomicReplace {
  param([string]$Source, [string]$Destination)
  $Backup = "$Destination.$(New-FoundationRandomId).replace-backup"
  try {
    [IO.File]::Replace($Source, $Destination, $Backup, $true)
  } finally {
    if (Test-Path -LiteralPath $Backup) { Remove-Item -LiteralPath $Backup -Force }
  }
}

function Write-FoundationJsonAtomic {
  param($Value, [string]$Path)
  $Temp = "$Path.$(New-FoundationRandomId).tmp"
  Write-CanonicalFoundationJsonExclusive $Value $Temp
  try {
    if (Test-Path -LiteralPath $Path) {
      Invoke-FoundationAtomicReplace $Temp $Path
    } else {
      [IO.File]::Move($Temp, $Path)
    }
  } finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Force }
  }
}

function Open-FoundationTransaction {
  param([Parameter(Mandatory = $true)]$Plan)
  if ($Plan.blocked) {
    Throw-FoundationError -Code 'USER_CONFLICT' -Message 'Blocked plan cannot open a transaction'
  }
  $StateRoot = Initialize-FoundationStateRoot $Plan.local_app_data
  $JournalPath = Join-Path $StateRoot 'transaction-journal.json'
  if (Test-Path -LiteralPath $JournalPath) {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'A pending transaction already exists'
  }
  $TransactionId = New-FoundationRandomId
  $SnapshotId = New-FoundationRandomId
  $SnapshotRoot = Join-Path $StateRoot "backups\$SnapshotId"
  New-FoundationSafeDirectory $SnapshotRoot
  $Journal = [pscustomobject][ordered]@{
    schema_version = 1
    kind = 'install'
    transaction_id = $TransactionId
    release_id = $Plan.release_id
    status = 'OPEN'
    next_step = 1
    snapshot_id = $SnapshotId
    plan_fingerprint = $Plan.plan_fingerprint
    created_paths = @()
    updated_paths = @()
    created_directories = @()
    created_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  Write-CanonicalFoundationJsonExclusive $Journal $JournalPath
  return [pscustomobject]@{
    state_root = $StateRoot
    journal_path = $JournalPath
    journal = $Journal
    transaction_id = $TransactionId
    snapshot_id = $SnapshotId
    snapshot_root = $SnapshotRoot
    plan = $Plan
  }
}

function Write-FoundationJournalStep {
  param($Context, [string]$Step, [AllowNull()]$Row = $null)
  $Journal = $Context.journal
  if ($Row -and $Step -like 'replace-*') {
    if ($Row.action -ceq 'CREATE') {
      $Journal.created_paths = @($Journal.created_paths) + @([string]$Row.destination_relative_path)
    } elseif ($Row.action -ceq 'MANAGED_UPDATE') {
      $Journal.updated_paths = @($Journal.updated_paths) + @([string]$Row.destination_relative_path)
    }
  }
  $Journal.next_step = [int]$Journal.next_step + 1
  Write-FoundationJsonAtomic $Journal $Context.journal_path
  $Context.journal = $Journal
}

function Write-FoundationActiveState {
  param($State, [string]$LocalAppData)
  $Path = Join-Path (Get-FoundationStateRoot $LocalAppData) 'state.json'
  Write-FoundationJsonAtomic $State $Path
}

function Remove-FoundationActiveState {
  param([string]$LocalAppData)
  $Path = Join-Path (Get-FoundationStateRoot $LocalAppData) 'state.json'
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
}

function Close-FoundationTransaction {
  param($Context, [string]$Result)
  $Journal = $Context.journal
  $Journal.status = $Result
  $Archive = Join-Path $Context.state_root (
    "releases\$($Journal.release_id)-$($Journal.transaction_id)-$($Result.ToLowerInvariant()).json"
  )
  Write-CanonicalFoundationJsonExclusive $Journal $Archive
  Remove-Item -LiteralPath $Context.journal_path -Force
}
