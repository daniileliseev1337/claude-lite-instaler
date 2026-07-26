function Assert-PlanStillCurrent {
  param($Plan)
  $Fresh = New-FoundationPlan $Plan.package_root $Plan.user_profile `
    $Plan.local_app_data $Plan.environment
  if ($Fresh.plan_fingerprint -cne $Plan.plan_fingerprint) {
    $Code = if ($Fresh.manifest_sha256 -cne $Plan.manifest_sha256) {
      'INVALID_PACKAGE'
    } else {
      'USER_CONFLICT'
    }
    Throw-FoundationError -Code $Code -Message 'Plan became stale before apply'
  }
}

function Save-FoundationSnapshot {
  param($Context, [object[]]$FileOperations)
  $PriorState = Read-FoundationActiveState $Context.plan.local_app_data `
    $Context.plan.target -AllowMissing
  $Rows = @()
  $BackupFilesRoot = Join-Path $Context.snapshot_root 'files'
  New-FoundationSafeDirectory $BackupFilesRoot
  $Sequence = 0
  foreach ($Operation in @($FileOperations | Where-Object action -in @('CREATE', 'MANAGED_UPDATE'))) {
    $Sequence++
    $BackupRelative = $null
    if ($Operation.action -ceq 'MANAGED_UPDATE') {
      $BackupRelative = "files/{0:D6}.bin" -f $Sequence
      $BackupPath = Join-Path $Context.snapshot_root ($BackupRelative.Replace('/', '\'))
      Copy-FoundationFileExclusive $Operation.destination $BackupPath
      if ((Get-Sha256Lower $BackupPath) -cne $Operation.prior_sha256) {
        Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Snapshot hash differs'
      }
    }
    $Rows += [pscustomobject][ordered]@{
      sequence = $Sequence
      component_id = $Operation.component_id
      destination_relative_path = $Operation.destination_relative_path
      operation = if ($Operation.action -ceq 'CREATE') { 'CREATED' } else { 'UPDATED' }
      prior_sha256 = $Operation.prior_sha256
      installed_sha256 = $Operation.expected_sha256
      backup_relative_path = $BackupRelative
    }
  }
  $Snapshot = [pscustomobject][ordered]@{
    schema_version = 1
    snapshot_id = $Context.snapshot_id
    release_id = $Context.plan.release_id
    prior_state = $PriorState
    rows = $Rows
    created_directories = @()
    created_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $SnapshotPath = Join-Path $Context.snapshot_root 'snapshot.json'
  Write-CanonicalFoundationJsonExclusive $Snapshot $SnapshotPath
  $Context | Add-Member -NotePropertyName snapshot -NotePropertyValue $Snapshot
  $Context | Add-Member -NotePropertyName snapshot_path -NotePropertyValue $SnapshotPath
  return $Snapshot
}

function Update-FoundationSnapshot {
  param($Context)
  Write-FoundationJsonAtomic $Context.snapshot $Context.snapshot_path
}

function Ensure-FoundationDestinationDirectory {
  param($Context, [string]$Destination)
  $Parent = [IO.Path]::GetFullPath((Split-Path -Parent $Destination))
  $ProfileRoot = [IO.Path]::GetFullPath($Context.plan.user_profile)
  if (-not $Parent.StartsWith(
      $ProfileRoot + [IO.Path]::DirectorySeparatorChar,
      [StringComparison]::OrdinalIgnoreCase)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Destination parent escaped profile'
  }
  $Missing = New-Object Collections.Generic.List[string]
  $Cursor = $Parent
  while (-not (Test-Path -LiteralPath $Cursor)) {
    $Missing.Add($Cursor)
    $Next = Split-Path -Parent $Cursor
    if ($Next -eq $Cursor -or -not $Next.StartsWith($ProfileRoot, [StringComparison]::OrdinalIgnoreCase)) {
      Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Could not find safe profile ancestor'
    }
    $Cursor = $Next
  }
  Assert-SafeExistingDirectory $Cursor
  for ($Index = $Missing.Count - 1; $Index -ge 0; $Index--) {
    $Directory = $Missing[$Index]
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    Assert-SafeExistingDirectory $Directory
    $Relative = $Directory.Substring($ProfileRoot.Length).TrimStart('\').Replace('\', '/')
    $Context.snapshot.created_directories = @($Context.snapshot.created_directories) + @($Relative)
    $Context.journal.created_directories = @($Context.journal.created_directories) + @($Relative)
    Update-FoundationSnapshot $Context
    Write-FoundationJsonAtomic $Context.journal $Context.journal_path
  }
  Assert-SafeExistingDirectory $Parent
}

function Write-FoundationStagingFile {
  param($Context, $Row, [string]$Payload)
  Ensure-FoundationDestinationDirectory $Context $Row.destination
  $Name = [IO.Path]::GetFileName($Row.destination)
  $Staged = Join-Path (Split-Path -Parent $Row.destination) (
    ".$Name.foundation-$($Context.transaction_id).tmp"
  )
  if (Test-Path -LiteralPath $Staged) {
    Throw-FoundationError -Code 'USER_CONFLICT' -Message 'Staging path already exists'
  }
  Copy-FoundationFileExclusive $Payload $Staged
  if ((Get-Sha256Lower $Staged) -cne $Row.expected_sha256) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Staged payload hash differs'
  }
  return $Staged
}

function Install-FoundationStagedFile {
  param($Context, $Row, [string]$Staged)
  Assert-SafeExistingDirectory (Split-Path -Parent $Row.destination)
  if ($Row.action -ceq 'CREATE') {
    if (Test-Path -LiteralPath $Row.destination) {
      Throw-FoundationError -Code 'USER_CONFLICT' -Message 'Create destination appeared after plan'
    }
    [IO.File]::Move($Staged, $Row.destination)
  } elseif ($Row.action -ceq 'MANAGED_UPDATE') {
    if (-not (Test-Path -LiteralPath $Row.destination -PathType Leaf) -or
        (Get-Sha256Lower $Row.destination) -cne $Row.prior_sha256) {
      Throw-FoundationError -Code 'USER_CONFLICT' -Message 'Managed destination changed after plan'
    }
    Invoke-FoundationAtomicReplace $Staged $Row.destination
  } else {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unexpected transaction action'
  }
  if ((Get-Sha256Lower $Row.destination) -cne $Row.expected_sha256) {
    Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Installed file hash differs'
  }
}

function Test-FoundationInstalledPlan {
  param($Plan)
  $Results = @()
  foreach ($Row in @($Plan.file_operations)) {
    $Status = if (-not (Test-Path -LiteralPath $Row.destination -PathType Leaf)) {
      'MISSING'
    } elseif ((Get-Sha256Lower $Row.destination) -cne $Row.expected_sha256) {
      'DRIFT'
    } else {
      'HEALTHY'
    }
    $Results += [pscustomobject]@{
      component_id = $Row.component_id
      path_id = $Row.path_id
      status = $Status
    }
  }
  return [pscustomobject]@{
    healthy = @($Results | Where-Object status -ne 'HEALTHY').Count -eq 0
    component_results = $Results
  }
}

function New-FoundationActiveStateFromPlan {
  param($Context)
  $Plan = $Context.plan
  $Manifest = Read-FoundationManifest (Join-Path $Plan.package_root 'release-manifest.json')
  $ActiveComponents = @(
    foreach ($Component in @($Manifest.components | Where-Object activation -CEQ 'ACTIVE_ELIGIBLE')) {
      [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        destination_relative_path = $Component.destination_relative_path
        sha256 = $Component.sha256
        bytes = [int64]$Component.bytes
      }
    }
  )
  $ActiveFiles = @(
    foreach ($Row in @($Plan.file_operations)) {
      [pscustomobject][ordered]@{
        component_id = $Row.component_id
        path_id = $Row.path_id
        destination_relative_path = $Row.destination_relative_path
        sha256 = $Row.expected_sha256
        bytes = [int64]$Row.bytes
      }
    }
  )
  $Quarantine = @(
    foreach ($Component in @($Manifest.components | Where-Object activation -CNE 'ACTIVE_ELIGIBLE')) {
      [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        activation = $Component.activation
        quarantine_reason = $Component.quarantine_reason
        sha256 = $Component.sha256
        evidence_ids = @($Component.evidence_ids)
      }
    }
  )
  return [pscustomobject][ordered]@{
    schema_version = 2
    release_id = $Plan.release_id
    target = $Plan.target
    install_role = $Plan.install_role
    manifest_sha256 = $Plan.manifest_sha256
    compatibility = $Manifest.compatibility
    sync_policy = $Manifest.sync_policy
    active_components = $ActiveComponents
    active_files = $ActiveFiles
    quarantine_components = $Quarantine
    rollback_snapshot_id = $Context.snapshot_id
    installed_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
}

function Invoke-FoundationInstall {
  param(
    [Parameter(Mandatory = $true)]$Plan,
    [scriptblock]$FailureInjector = {}
  )
  if ($Plan.blocked) {
    Throw-FoundationError -Code 'USER_CONFLICT' -Message 'Blocked plan cannot install'
  }
  Assert-PlanStillCurrent $Plan
  $Changed = @($Plan.file_operations | Where-Object action -in @('CREATE', 'MANAGED_UPDATE'))
  if ($Changed.Count -eq 0) {
    $Doctor = Test-FoundationInstalledPlan $Plan
    if (-not $Doctor.healthy) {
      Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Idempotent plan is not healthy'
    }
    return [pscustomobject]@{
      release_id = $Plan.release_id
      installed = $false
      doctor = $Doctor
    }
  }

  $Context = Open-FoundationTransaction $Plan
  try {
    $null = Save-FoundationSnapshot $Context $Plan.file_operations
    & $FailureInjector 'after-snapshot'
    $Ordinal = 0
    foreach ($Row in $Changed) {
      $Ordinal++
      $Staged = Write-FoundationStagingFile $Context $Row $Row.payload_path
      & $FailureInjector "after-stage-$Ordinal"
      Write-FoundationJournalStep $Context "replace-$Ordinal" $Row
      & $FailureInjector "after-intent-$Ordinal"
      Install-FoundationStagedFile $Context $Row $Staged
      & $FailureInjector "after-replace-$Ordinal"
    }
    & $FailureInjector 'before-doctor'
    $Doctor = Test-FoundationInstalledPlan $Plan
    if (-not $Doctor.healthy) {
      Throw-FoundationError -Code 'ACTIVE_DRIFT' -Message 'Post-install doctor failed'
    }
    & $FailureInjector 'after-doctor'
    & $FailureInjector 'before-state'
    $State = New-FoundationActiveStateFromPlan $Context
    Write-FoundationActiveState $State $Plan.local_app_data $Plan.target
    & $FailureInjector 'after-state'
    & $FailureInjector 'before-close'
    Close-FoundationTransaction $Context 'COMMITTED' $FailureInjector
    return [pscustomobject]@{
      release_id = $Plan.release_id
      installed = $true
      doctor = $Doctor
    }
  } catch {
    throw
  }
}
