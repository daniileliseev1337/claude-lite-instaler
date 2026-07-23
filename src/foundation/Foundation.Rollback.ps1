function Read-FoundationSnapshot {
  param([string]$LocalAppData, [string]$SnapshotId)
  if ($SnapshotId -notmatch '^[0-9a-f]{64}$') {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot ID is invalid'
  }
  $Root = Join-Path (Get-FoundationStateRoot $LocalAppData) "backups\$SnapshotId"
  $Path = Join-Path $Root 'snapshot.json'
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot metadata is missing'
  }
  $Snapshot = Read-JsonFileStrict $Path 8388608
  Assert-ExactProperties $Snapshot @(
    'schema_version', 'snapshot_id', 'release_id', 'prior_state', 'rows',
    'created_directories', 'created_at_utc'
  ) 'snapshot'
  if ($Snapshot.schema_version -ne 1 -or $Snapshot.snapshot_id -cne $SnapshotId) {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot identity differs'
  }
  foreach ($Row in @($Snapshot.rows)) {
    Assert-ExactProperties $Row @(
      'sequence', 'component_id', 'destination_relative_path', 'operation',
      'prior_sha256', 'installed_sha256', 'backup_relative_path'
    ) 'snapshot row'
    if (@('CREATED', 'UPDATED') -cnotcontains [string]$Row.operation -or
        $Row.installed_sha256 -notmatch '^[0-9a-f]{64}$') {
      Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot row is invalid'
    }
    if ($Row.operation -ceq 'UPDATED') {
      $Backup = Join-Path $Root (([string]$Row.backup_relative_path).Replace('/', '\'))
      if (-not (Test-Path -LiteralPath $Backup -PathType Leaf) -or
          (Get-Sha256Lower $Backup) -cne $Row.prior_sha256) {
        Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot backup is invalid'
      }
    }
  }
  return [pscustomobject]@{ root=$Root; path=$Path; snapshot=$Snapshot }
}

function Write-FoundationRecoveryMetadata {
  param([string]$LocalAppData, $Row, [string]$Code)
  $Root = Initialize-FoundationStateRoot $LocalAppData
  $Path = Join-Path $Root ("recovery\rollback-{0}.json" -f (New-FoundationRandomId))
  $Record = [pscustomobject][ordered]@{
    schema_version = 1
    kind = 'foundation_rollback_conflict'
    code = $Code
    component_id = $Row.component_id
    destination_relative_path = $Row.destination_relative_path
    expected_installed_sha256 = $Row.installed_sha256
    generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  Write-CanonicalFoundationJsonExclusive $Record $Path
}

function Open-FoundationRollbackJournal {
  param([string]$LocalAppData, [string]$ReleaseId, [string]$SnapshotId)
  $StateRoot = Initialize-FoundationStateRoot $LocalAppData
  $Path = Join-Path $StateRoot 'transaction-journal.json'
  if (Test-Path -LiteralPath $Path) {
    $Journal = Read-FoundationJournal $LocalAppData
    return [pscustomobject]@{
      state_root=$StateRoot
      journal_path=$Path
      journal=$Journal
      transaction_id=$Journal.transaction_id
      snapshot_id=$Journal.snapshot_id
    }
  }
  $Journal = [pscustomobject][ordered]@{
    schema_version = 1
    kind = 'rollback'
    transaction_id = New-FoundationRandomId
    release_id = $ReleaseId
    status = 'OPEN'
    next_step = 1
    snapshot_id = $SnapshotId
    plan_fingerprint = 'rollback'
    created_paths = @()
    updated_paths = @()
    created_directories = @()
    created_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  Write-CanonicalFoundationJsonExclusive $Journal $Path
  return [pscustomobject]@{
    state_root=$StateRoot
    journal_path=$Path
    journal=$Journal
    transaction_id=$Journal.transaction_id
    snapshot_id=$SnapshotId
  }
}

function Invoke-FoundationRollback {
  param(
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData
  )
  $Pending = Test-PendingFoundationJournal $LocalAppData
  $State = Read-FoundationActiveState $LocalAppData -AllowMissing
  if ($Pending) {
    $ExistingJournal = Read-FoundationJournal $LocalAppData
    $SnapshotId = [string]$ExistingJournal.snapshot_id
    $ReleaseId = [string]$ExistingJournal.release_id
  } elseif ($null -ne $State) {
    $SnapshotId = [string]$State.rollback_snapshot_id
    $ReleaseId = [string]$State.release_id
    $ExistingJournal = $null
  } else {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'No installed or interrupted release to roll back'
  }
  $SnapshotContext = Read-FoundationSnapshot $LocalAppData $SnapshotId
  $Snapshot = $SnapshotContext.snapshot
  $AppliedCreated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $AppliedUpdated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  if ($Pending) {
    foreach ($Path in @($ExistingJournal.created_paths)) { $null = $AppliedCreated.Add([string]$Path) }
    foreach ($Path in @($ExistingJournal.updated_paths)) { $null = $AppliedUpdated.Add([string]$Path) }
  } else {
    foreach ($Row in @($Snapshot.rows)) {
      if ($Row.operation -ceq 'CREATED') { $null = $AppliedCreated.Add([string]$Row.destination_relative_path) }
      else { $null = $AppliedUpdated.Add([string]$Row.destination_relative_path) }
    }
  }

  foreach ($Row in @($Snapshot.rows)) {
    $Applied = if ($Row.operation -ceq 'CREATED') {
      $AppliedCreated.Contains([string]$Row.destination_relative_path)
    } else {
      $AppliedUpdated.Contains([string]$Row.destination_relative_path)
    }
    if (-not $Applied) { continue }
    $Destination = Resolve-ManagedDestination $Row.destination_relative_path $UserProfile
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
        (Get-Sha256Lower $Destination) -cne $Row.installed_sha256) {
      Write-FoundationRecoveryMetadata $LocalAppData $Row 'ROLLBACK_CONFLICT'
      Throw-FoundationError -Code 'ROLLBACK_CONFLICT' -Message "Managed file changed: $($Row.component_id)"
    }
  }

  $Context = Open-FoundationRollbackJournal $LocalAppData $ReleaseId $SnapshotId
  foreach ($Row in @($Snapshot.rows | Sort-Object sequence -Descending)) {
    $Applied = if ($Row.operation -ceq 'CREATED') {
      $AppliedCreated.Contains([string]$Row.destination_relative_path)
    } else {
      $AppliedUpdated.Contains([string]$Row.destination_relative_path)
    }
    if (-not $Applied) { continue }
    $Destination = Resolve-ManagedDestination $Row.destination_relative_path $UserProfile
    if ($Row.operation -ceq 'CREATED') {
      Remove-Item -LiteralPath $Destination -Force
    } else {
      $Backup = Join-Path $SnapshotContext.root (([string]$Row.backup_relative_path).Replace('/', '\'))
      $Staged = Join-Path (Split-Path -Parent $Destination) (
        ".$([IO.Path]::GetFileName($Destination)).rollback-$($Context.transaction_id).tmp"
      )
      Copy-FoundationFileExclusive $Backup $Staged
      Invoke-FoundationAtomicReplace $Staged $Destination
      if ((Get-Sha256Lower $Destination) -cne $Row.prior_sha256) {
        Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Restored file hash differs'
      }
    }
  }

  $ProfileRoot = [IO.Path]::GetFullPath($UserProfile)
  $Directories = @($Snapshot.created_directories | Sort-Object { $_.Length } -Descending)
  foreach ($Relative in $Directories) {
    $Directory = [IO.Path]::GetFullPath((Join-Path $ProfileRoot ($Relative.Replace('/', '\'))))
    if (-not $Directory.StartsWith(
        $ProfileRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
      Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Snapshot directory escaped profile'
    }
    if (Test-Path -LiteralPath $Directory -PathType Container) {
      $Children = @(Get-ChildItem -LiteralPath $Directory -Force)
      if ($Children.Count -eq 0) { Remove-Item -LiteralPath $Directory -Force }
    }
  }
  if ($null -eq $Snapshot.prior_state) {
    Remove-FoundationActiveState $LocalAppData
  } else {
    Write-FoundationActiveState $Snapshot.prior_state $LocalAppData
  }
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null $null -IgnorePendingJournal
  if (-not $Doctor.healthy) {
    Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Rollback doctor failed'
  }
  Close-FoundationTransaction $Context 'ROLLED_BACK'
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null
  return [pscustomobject]@{
    rolled_back = $true
    release_id = $Doctor.release_id
    doctor = $Doctor
  }
}
