function Read-FoundationSnapshot {
  param([string]$LocalAppData, [string]$Target, [string]$SnapshotId)
  if ($SnapshotId -notmatch '^[0-9a-f]{64}$') {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'Snapshot ID is invalid'
  }
  $Root = Join-Path (Get-FoundationStateRoot $LocalAppData $Target) "backups\$SnapshotId"
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
  param([string]$LocalAppData, [string]$Target, $Row, [string]$Code)
  $Root = Initialize-FoundationStateRoot $LocalAppData $Target
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
  param(
    [string]$LocalAppData,
    [string]$Target,
    [string]$ReleaseId,
    [string]$SnapshotId,
    [string[]]$CreatedPaths = @(),
    [string[]]$UpdatedPaths = @()
  )
  $StateRoot = Initialize-FoundationStateRoot $LocalAppData $Target
  $Path = Join-Path $StateRoot 'transaction-journal.json'
  if (Test-Path -LiteralPath $Path) {
    $Journal = Read-FoundationJournal $LocalAppData $Target
    if ($Journal.release_id -cne $ReleaseId -or
        $Journal.snapshot_id -cne $SnapshotId -or
        @('install', 'rollback') -cnotcontains [string]$Journal.kind) {
      Throw-FoundationError -Code 'RECOVERY_REQUIRED' `
        -Message 'Pending journal does not match rollback snapshot'
    }
    if ($Journal.kind -ceq 'install') {
      $Journal.kind = 'rollback'
      $Journal.transaction_id = New-FoundationRandomId
      $Journal.plan_fingerprint = 'rollback'
      $Journal.next_step = 1
    }
    $Journal.created_paths = @($CreatedPaths | Sort-Object)
    $Journal.updated_paths = @($UpdatedPaths | Sort-Object)
    Write-FoundationJsonAtomic $Journal $Path
  } else {
    $Journal = [pscustomobject][ordered]@{
      schema_version = 1
      kind = 'rollback'
      transaction_id = New-FoundationRandomId
      release_id = $ReleaseId
      status = 'OPEN'
      next_step = 1
      snapshot_id = $SnapshotId
      plan_fingerprint = 'rollback'
      created_paths = @($CreatedPaths | Sort-Object)
      updated_paths = @($UpdatedPaths | Sort-Object)
      created_directories = @()
      created_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    Write-CanonicalFoundationJsonExclusive $Journal $Path
  }
  return [pscustomobject]@{
    state_root=$StateRoot
    journal_path=$Path
    journal=$Journal
    transaction_id=$Journal.transaction_id
    snapshot_id=$SnapshotId
  }
}

function Write-FoundationRollbackProgress {
  param($Context, $CreatedPaths, $UpdatedPaths)
  $Context.journal.created_paths = @($CreatedPaths | Sort-Object)
  $Context.journal.updated_paths = @($UpdatedPaths | Sort-Object)
  $Context.journal.next_step = [int]$Context.journal.next_step + 1
  Write-FoundationJsonAtomic $Context.journal $Context.journal_path
}

function Remove-FoundationInterruptedStagingFiles {
  param(
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)]$Journal,
    [Parameter(Mandatory = $true)]$Snapshot
  )
  foreach ($Row in @($Snapshot.rows)) {
    $Destination = Resolve-ManagedDestination `
      $Row.destination_relative_path $UserProfile
    $Parent = Split-Path -Parent $Destination
    $Name = [IO.Path]::GetFileName($Destination)
    $Staged = Join-Path $Parent (
      ".$Name.foundation-$($Journal.transaction_id).tmp"
    )
    if (-not (Test-Path -LiteralPath $Staged)) { continue }
    Assert-SafeExistingDirectory $Parent
    $Item = Get-Item -LiteralPath $Staged -Force -ErrorAction Stop
    if ($Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-Sha256Lower $Staged) -cne $Row.installed_sha256) {
      Write-FoundationRecoveryMetadata $LocalAppData $Target $Row 'ROLLBACK_CONFLICT'
      Throw-FoundationError -Code 'ROLLBACK_CONFLICT' `
        -Message "Staging file changed: $($Row.component_id)"
    }
    Remove-Item -LiteralPath $Staged -Force
  }
}

function Remove-FoundationInterruptedRollbackStagingFiles {
  param(
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)]$Journal,
    [Parameter(Mandatory = $true)]$Snapshot
  )
  foreach ($Row in @($Snapshot.rows | Where-Object operation -CEQ 'UPDATED')) {
    $Destination = Resolve-ManagedDestination `
      $Row.destination_relative_path $UserProfile
    $Parent = Split-Path -Parent $Destination
    $Name = [IO.Path]::GetFileName($Destination)
    $Staged = Join-Path $Parent (
      ".$Name.rollback-$($Journal.transaction_id).tmp"
    )
    if (-not (Test-Path -LiteralPath $Staged)) { continue }
    Assert-SafeExistingDirectory $Parent
    $Item = Get-Item -LiteralPath $Staged -Force -ErrorAction Stop
    if ($Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Get-Sha256Lower $Staged) -cne $Row.prior_sha256) {
      Write-FoundationRecoveryMetadata $LocalAppData $Target $Row 'ROLLBACK_CONFLICT'
      Throw-FoundationError -Code 'ROLLBACK_CONFLICT' `
        -Message "Rollback staging file changed: $($Row.component_id)"
    }
    Remove-Item -LiteralPath $Staged -Force
  }
}

function Invoke-FoundationRollback {
  param(
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [Parameter(Mandatory = $true)][string]$Target,
    [scriptblock]$FailureInjector = {}
  )
  Assert-FoundationTarget $Target
  $Pending = Test-PendingFoundationJournal $LocalAppData $Target
  $State = Read-FoundationActiveState $LocalAppData $Target -AllowMissing
  if ($Pending) {
    $ExistingJournal = Read-FoundationJournal $LocalAppData $Target
    $SnapshotId = [string]$ExistingJournal.snapshot_id
    $ReleaseId = [string]$ExistingJournal.release_id
  } elseif ($null -ne $State) {
    $SnapshotId = [string]$State.rollback_snapshot_id
    $ReleaseId = [string]$State.release_id
    $ExistingJournal = $null
  } else {
    Throw-FoundationError -Code 'RECOVERY_REQUIRED' -Message 'No installed or interrupted release to roll back'
  }
  $SnapshotContext = Read-FoundationSnapshot $LocalAppData $Target $SnapshotId
  $Snapshot = $SnapshotContext.snapshot
  $PendingKind = if ($Pending) { [string]$ExistingJournal.kind } else { 'committed' }
  if ($PendingKind -ceq 'install') {
    Remove-FoundationInterruptedStagingFiles $UserProfile $LocalAppData $Target `
      $ExistingJournal $Snapshot
  } elseif ($PendingKind -ceq 'rollback') {
    Remove-FoundationInterruptedRollbackStagingFiles $UserProfile $LocalAppData `
      $Target $ExistingJournal $Snapshot
  }
  $AppliedCreated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $AppliedUpdated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  if ($Pending) {
    foreach ($Path in @($ExistingJournal.created_paths)) { $null = $AppliedCreated.Add([string]$Path) }
    foreach ($Path in @($ExistingJournal.updated_paths)) { $null = $AppliedUpdated.Add([string]$Path) }
    foreach ($Row in @($Snapshot.rows)) {
      $Relative = [string]$Row.destination_relative_path
      $IsPendingPath = if ($Row.operation -ceq 'CREATED') {
        $AppliedCreated.Contains($Relative)
      } else {
        $AppliedUpdated.Contains($Relative)
      }

      $Destination = Resolve-ManagedDestination $Relative $UserProfile
      $Exists = Test-Path -LiteralPath $Destination
      $IsFile = Test-Path -LiteralPath $Destination -PathType Leaf
      $ActualHash = if ($IsFile) { Get-Sha256Lower $Destination } else { $null }
      $WasApplied = $false
      $Conflict = $false
      if ($PendingKind -ceq 'install') {
        if (-not $IsPendingPath) { continue }
        if ($Row.operation -ceq 'CREATED') {
          if (-not $Exists) {
            $WasApplied = $false
          } elseif ($IsFile -and $ActualHash -ceq $Row.installed_sha256) {
            $WasApplied = $true
          } else {
            $Conflict = $true
          }
        } else {
          if (-not $IsFile) {
            $Conflict = $true
          } elseif ($ActualHash -ceq $Row.prior_sha256) {
            $WasApplied = $false
          } elseif ($ActualHash -ceq $Row.installed_sha256) {
            $WasApplied = $true
          } else {
            $Conflict = $true
          }
        }
      } else {
        if ($Row.operation -ceq 'CREATED') {
          if (-not $Exists) {
            $WasApplied = $false
          } elseif ($IsPendingPath -and $IsFile -and
              $ActualHash -ceq $Row.installed_sha256) {
            $WasApplied = $true
          } else {
            $Conflict = $true
          }
        } else {
          if (-not $IsFile) {
            $Conflict = $true
          } elseif ($ActualHash -ceq $Row.prior_sha256) {
            $WasApplied = $false
          } elseif ($IsPendingPath -and
              $ActualHash -ceq $Row.installed_sha256) {
            $WasApplied = $true
          } else {
            $Conflict = $true
          }
        }
      }
      if ($Conflict) {
        Write-FoundationRecoveryMetadata $LocalAppData $Target $Row 'ROLLBACK_CONFLICT'
        Throw-FoundationError -Code 'ROLLBACK_CONFLICT' `
          -Message "Managed file state is ambiguous: $($Row.component_id)"
      }
      if (-not $WasApplied) {
        if ($Row.operation -ceq 'CREATED') {
          $null = $AppliedCreated.Remove($Relative)
        } else {
          $null = $AppliedUpdated.Remove($Relative)
        }
      }
    }
  } else {
    foreach ($Row in @($Snapshot.rows)) {
      if ($Row.operation -ceq 'CREATED') { $null = $AppliedCreated.Add([string]$Row.destination_relative_path) }
      else { $null = $AppliedUpdated.Add([string]$Row.destination_relative_path) }
    }
    foreach ($Row in @($Snapshot.rows)) {
      $Destination = Resolve-ManagedDestination `
        $Row.destination_relative_path $UserProfile
      if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
          (Get-Sha256Lower $Destination) -cne $Row.installed_sha256) {
        Write-FoundationRecoveryMetadata $LocalAppData $Target $Row `
          'ROLLBACK_CONFLICT'
        Throw-FoundationError -Code 'ROLLBACK_CONFLICT' `
          -Message "Managed file changed: $($Row.component_id)"
      }
    }
  }

  $Context = Open-FoundationRollbackJournal $LocalAppData $Target $ReleaseId `
    $SnapshotId @($AppliedCreated) @($AppliedUpdated)
  & $FailureInjector 'after-open'
  $Ordinal = 0
  foreach ($Row in @($Snapshot.rows | Sort-Object sequence -Descending)) {
    $Applied = if ($Row.operation -ceq 'CREATED') {
      $AppliedCreated.Contains([string]$Row.destination_relative_path)
    } else {
      $AppliedUpdated.Contains([string]$Row.destination_relative_path)
    }
    if (-not $Applied) { continue }
    $Ordinal++
    $Destination = Resolve-ManagedDestination $Row.destination_relative_path $UserProfile
    if ($Row.operation -ceq 'CREATED') {
      Remove-Item -LiteralPath $Destination -Force
    } else {
      $Backup = Join-Path $SnapshotContext.root (([string]$Row.backup_relative_path).Replace('/', '\'))
      $Staged = Join-Path (Split-Path -Parent $Destination) (
        ".$([IO.Path]::GetFileName($Destination)).rollback-$($Context.transaction_id).tmp"
      )
      Copy-FoundationFileExclusive $Backup $Staged
      & $FailureInjector "after-stage-$Ordinal"
      Invoke-FoundationAtomicReplace $Staged $Destination
      if ((Get-Sha256Lower $Destination) -cne $Row.prior_sha256) {
        Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Restored file hash differs'
      }
    }
    & $FailureInjector "after-file-$Ordinal"
    if ($Row.operation -ceq 'CREATED') {
      $null = $AppliedCreated.Remove([string]$Row.destination_relative_path)
    } else {
      $null = $AppliedUpdated.Remove([string]$Row.destination_relative_path)
    }
    Write-FoundationRollbackProgress $Context $AppliedCreated $AppliedUpdated
    & $FailureInjector "after-progress-$Ordinal"
  }

  & $FailureInjector 'before-directories'
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
  & $FailureInjector 'after-directories'
  & $FailureInjector 'before-state'
  if ($null -eq $Snapshot.prior_state) {
    Remove-FoundationActiveState $LocalAppData $Target
  } else {
    Write-FoundationActiveState $Snapshot.prior_state $LocalAppData $Target
  }
  & $FailureInjector 'after-state'
  & $FailureInjector 'before-doctor'
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null $null `
    -Target $Target -IgnorePendingJournal
  if (-not $Doctor.healthy) {
    Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Rollback doctor failed'
  }
  & $FailureInjector 'after-doctor'
  & $FailureInjector 'before-close'
  Close-FoundationTransaction $Context 'ROLLED_BACK' $FailureInjector
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null $null `
    -Target $Target
  return [pscustomobject]@{
    rolled_back = $true
    release_id = $Doctor.release_id
    doctor = $Doctor
  }
}
