function Test-FoundationEnvironmentCompatibility {
  param($Manifest, $Environment)
  if ($null -eq $Environment -or -not [bool]$Environment.codex_detected) { return $false }
  return (
    @($Manifest.compatibility.windows) -ccontains [string]$Environment.windows
  ) -and (
    @($Manifest.compatibility.powershell) -ccontains [string]$Environment.powershell
  ) -and (
    @($Manifest.compatibility.codex_versions) -ccontains [string]$Environment.codex_version
  )
}

function Get-FoundationComponentPayloadFiles {
  param($Manifest, $Component)
  $Rows = @(
    $Manifest.files | Where-Object {
      $_.role -ceq 'component' -and $_.component_id -ceq $Component.component_id
    }
  )
  $Result = @()
  foreach ($Row in $Rows) {
    $Relative = if ($Row.path -ceq $Component.payload_relative_path) {
      ''
    } else {
      ([string]$Row.path).Substring(([string]$Component.payload_relative_path).Length + 1)
    }
    $DestinationRelative = if ([string]::IsNullOrEmpty($Relative)) {
      [string]$Component.destination_relative_path
    } else {
      "$($Component.destination_relative_path)/$Relative"
    }
    $Result += [pscustomobject]@{
      component_id = [string]$Component.component_id
      relative_path = $Relative
      payload_relative_path = [string]$Row.path
      destination_relative_path = $DestinationRelative
      sha256 = [string]$Row.sha256
      bytes = [int64]$Row.bytes
    }
  }
  return $Result
}

function Get-FoundationStateComponentIndex {
  param($State)
  $Index = @{}
  if ($null -eq $State) { return $Index }
  foreach ($Component in @($State.active_components)) {
    $Index[[string]$Component.component_id] = $Component
  }
  return $Index
}

function Get-FoundationStateFileIndex {
  param($State)
  $Index = @{}
  if ($null -eq $State) { return $Index }
  foreach ($File in @($State.active_files)) {
    $Index[[string]$File.destination_relative_path] = $File
  }
  return $Index
}

function Test-FoundationOwnedTreeExact {
  param(
    [string]$ComponentRoot,
    [object[]]$StateFiles,
    [string]$UserProfile
  )
  if (-not (Test-Path -LiteralPath $ComponentRoot)) { return $false }
  $Item = Get-Item -LiteralPath $ComponentRoot -Force
  if (-not $Item.PSIsContainer) { return $true }
  if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
  $Expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($File in $StateFiles) {
    $Absolute = Resolve-ManagedDestination $File.destination_relative_path $UserProfile
    $null = $Expected.Add([IO.Path]::GetFullPath($Absolute))
  }
  $Actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $Pending = [Collections.Generic.Queue[string]]::new()
  $Pending.Enqueue([IO.Path]::GetFullPath($ComponentRoot))
  while ($Pending.Count -gt 0) {
    $Directory = $Pending.Dequeue()
    $DirectoryItem = Get-Item -LiteralPath $Directory -Force
    if ($DirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    foreach ($Child in @(Get-ChildItem -LiteralPath $Directory -Force)) {
      if ($Child.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
      if ($Child.PSIsContainer) { $Pending.Enqueue($Child.FullName) }
      else { $null = $Actual.Add([IO.Path]::GetFullPath($Child.FullName)) }
    }
  }
  return $Actual.Count -eq $Expected.Count -and
    @($Actual | Where-Object { -not $Expected.Contains($_) }).Count -eq 0
}

function New-FoundationPlan {
  param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [Parameter(Mandatory = $true)]$Environment
  )
  $ManifestPath = Join-Path $PackageRoot 'release-manifest.json'
  $Manifest = Read-FoundationManifest $ManifestPath
  $Verification = Test-FoundationPackage $PackageRoot $Manifest
  $ProfileRoot = [IO.Path]::GetFullPath($UserProfile)
  $LocalRoot = [IO.Path]::GetFullPath($LocalAppData)
  $Rows = @()
  $FileOperations = @()
  $Blockers = @()

  if (-not (Test-FoundationEnvironmentCompatibility $Manifest $Environment)) {
    $Blockers += [pscustomobject]@{
      code = 'UNSUPPORTED_ENVIRONMENT'
      component_id = $null
      message = 'Windows, PowerShell or Codex version is unsupported'
    }
  }
  $StateRoot = Get-FoundationStateRoot $LocalRoot
  if (Test-Path -LiteralPath (Join-Path $StateRoot 'transaction-journal.json')) {
    $Blockers += [pscustomobject]@{
      code = 'RECOVERY_REQUIRED'
      component_id = $null
      message = 'Pending transaction journal exists'
    }
  }
  $State = Read-FoundationActiveState $LocalRoot -AllowMissing
  $StateComponents = Get-FoundationStateComponentIndex $State
  $StateFiles = Get-FoundationStateFileIndex $State
  $NextActiveIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

  foreach ($Component in @($Manifest.components)) {
    if ($Component.activation -cne 'ACTIVE_ELIGIBLE') {
      $Rows += [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        action = 'QUARANTINE'
        destination = $null
        quarantine_reason = $Component.quarantine_reason
      }
      continue
    }
    $null = $NextActiveIds.Add([string]$Component.component_id)
    $DestinationRoot = Resolve-ManagedDestination $Component.destination_relative_path $ProfileRoot
    $PayloadFiles = @(Get-FoundationComponentPayloadFiles $Manifest $Component)
    $CurrentComponent = $StateComponents[[string]$Component.component_id]
    $ComponentOperations = @()
    $ComponentConflict = $false

    if ($null -eq $CurrentComponent) {
      if (Test-Path -LiteralPath $DestinationRoot) {
        $ComponentConflict = $true
      } else {
        foreach ($File in $PayloadFiles) {
          $Destination = Resolve-ManagedDestination $File.destination_relative_path $ProfileRoot
          $Payload = Join-Path $PackageRoot ($File.payload_relative_path.Replace('/', '\'))
          $ComponentOperations += [pscustomobject][ordered]@{
            component_id = $Component.component_id
            path_id = "$($Component.component_id):$($File.relative_path)"
            action = 'CREATE'
            payload_path = [IO.Path]::GetFullPath($Payload)
            destination = $Destination
            destination_relative_path = $File.destination_relative_path
            prior_sha256 = $null
            expected_sha256 = $File.sha256
            bytes = $File.bytes
          }
        }
      }
    } else {
      if ($CurrentComponent.destination_relative_path -cne $Component.destination_relative_path) {
        $ComponentConflict = $true
      }
      $CurrentFilesForComponent = @(
        @($State.active_files) | Where-Object component_id -CEQ $Component.component_id
      )
      if (-not $ComponentConflict -and
          -not (Test-FoundationOwnedTreeExact $DestinationRoot $CurrentFilesForComponent $ProfileRoot)) {
        $ComponentConflict = $true
      }
      $NextDestinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
      foreach ($File in $PayloadFiles) {
        $null = $NextDestinations.Add([string]$File.destination_relative_path)
        $Destination = Resolve-ManagedDestination $File.destination_relative_path $ProfileRoot
        $Payload = Join-Path $PackageRoot ($File.payload_relative_path.Replace('/', '\'))
        $CurrentFile = $StateFiles[[string]$File.destination_relative_path]
        if ($null -eq $CurrentFile) {
          if (Test-Path -LiteralPath $Destination) { $ComponentConflict = $true; continue }
          $Action = 'CREATE'
          $PriorHash = $null
        } else {
          if (-not (Test-Path -LiteralPath $Destination -PathType Leaf) -or
              (Get-Sha256Lower $Destination) -cne $CurrentFile.sha256) {
            $ComponentConflict = $true
            continue
          }
          $PriorHash = [string]$CurrentFile.sha256
          $Action = if ($PriorHash -ceq $File.sha256) { 'UNCHANGED' } else { 'MANAGED_UPDATE' }
        }
        $ComponentOperations += [pscustomobject][ordered]@{
          component_id = $Component.component_id
          path_id = "$($Component.component_id):$($File.relative_path)"
          action = $Action
          payload_path = [IO.Path]::GetFullPath($Payload)
          destination = $Destination
          destination_relative_path = $File.destination_relative_path
          prior_sha256 = $PriorHash
          expected_sha256 = $File.sha256
          bytes = $File.bytes
        }
      }
      foreach ($CurrentFile in $CurrentFilesForComponent) {
        if (-not $NextDestinations.Contains([string]$CurrentFile.destination_relative_path)) {
          $ComponentConflict = $true
        }
      }
    }
    if ($ComponentConflict) {
      $Rows += [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        action = 'USER_CONFLICT'
        destination = $DestinationRoot
        quarantine_reason = $null
      }
      $Blockers += [pscustomobject]@{
        code = 'USER_CONFLICT'
        component_id = $Component.component_id
        message = 'Destination is unknown, drifted or contains extra files'
      }
      continue
    }
    $FileOperations += $ComponentOperations
    $Actions = @($ComponentOperations.action)
    $SummaryAction = if ($Actions -contains 'MANAGED_UPDATE') {
      'MANAGED_UPDATE'
    } elseif ($Actions -contains 'CREATE') {
      'CREATE'
    } else {
      'UNCHANGED'
    }
    $Rows += [pscustomobject][ordered]@{
      component_id = $Component.component_id
      component_type = $Component.component_type
      action = $SummaryAction
      destination = $DestinationRoot
      quarantine_reason = $null
    }
  }
  if ($null -ne $State) {
    foreach ($CurrentComponent in @($State.active_components)) {
      if (-not $NextActiveIds.Contains([string]$CurrentComponent.component_id)) {
        $Blockers += [pscustomobject]@{
          code = 'USER_CONFLICT'
          component_id = $CurrentComponent.component_id
          message = 'Foundation v1 does not retire an active component during upgrade'
        }
      }
    }
  }
  $Plan = [pscustomobject][ordered]@{
    release_id = $Manifest.release_id
    manifest_sha256 = Get-Sha256Lower $ManifestPath
    package_root = [IO.Path]::GetFullPath($PackageRoot)
    user_profile = $ProfileRoot
    local_app_data = $LocalRoot
    environment = [pscustomobject][ordered]@{
      windows = [string]$Environment.windows
      powershell = [string]$Environment.powershell
      codex_version = [string]$Environment.codex_version
      codex_detected = [bool]$Environment.codex_detected
    }
    rows = $Rows
    file_operations = $FileOperations
    blockers = $Blockers
    blocked = ($Blockers.Count -gt 0)
    package_verification = $Verification
    rollback_scope = @($FileOperations | Where-Object action -in @('CREATE', 'MANAGED_UPDATE') |
      ForEach-Object destination_relative_path)
  }
  $Plan | Add-Member -NotePropertyName plan_fingerprint -NotePropertyValue (
    Get-FoundationPlanFingerprint $Plan
  )
  return $Plan
}

function Get-FoundationPlanFingerprint {
  param($Plan)
  $Projection = [pscustomobject][ordered]@{
    release_id = $Plan.release_id
    manifest_sha256 = $Plan.manifest_sha256
    package_root = $Plan.package_root
    user_profile = $Plan.user_profile
    local_app_data = $Plan.local_app_data
    environment = $Plan.environment
    rows = $Plan.rows
    file_operations = $Plan.file_operations
    blockers = $Plan.blockers
    blocked = [bool]$Plan.blocked
  }
  return Get-FoundationSha256Hex (
    [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-FoundationCanonicalJson $Projection))
  )
}

