function Merge-FoundationComponentHealth {
  param([object[]]$Components, [object[]]$FileResults)
  return @(
    foreach ($Component in @($Components)) {
      $Rows = @($FileResults | Where-Object component_id -CEQ $Component.component_id)
      $Status = if ($Rows.Count -eq 0 -or @($Rows | Where-Object status -ne 'HEALTHY').Count -gt 0) {
        'DRIFT'
      } else {
        'HEALTHY'
      }
      [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        status = $Status
      }
    }
  )
}

function Get-FoundationQuarantineCounts {
  param([object[]]$Components)
  $ByActivation = [ordered]@{}
  $Raw = Get-FoundationAggregateMap $Components 'activation'
  $Keys = [string[]]@($Raw.Keys)
  [Array]::Sort($Keys, [StringComparer]::Ordinal)
  foreach ($Key in $Keys) { $ByActivation[$Key] = [int]$Raw[$Key] }
  return [pscustomobject][ordered]@{
    total = @($Components).Count
    by_activation = [pscustomobject]$ByActivation
  }
}

function Invoke-FoundationDoctor {
  param(
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [AllowNull()][string]$ExportReportPath,
    [AllowNull()]$Environment = $null,
    [switch]$IgnorePendingJournal
  )
  $State = Read-FoundationActiveState $LocalAppData -AllowMissing
  $Pending = (Test-PendingFoundationJournal $LocalAppData) -and -not $IgnorePendingJournal
  if ($null -eq $State) {
    $Errors = if ($Pending) { @('RECOVERY_REQUIRED') } else { @() }
    $Result = [pscustomobject][ordered]@{
      healthy = (-not $Pending)
      release_id = $null
      status = if ($Pending) { 'RECOVERY_REQUIRED' } else { 'NOT_INSTALLED' }
      component_results = @()
      error_codes = $Errors
      active_counts = [pscustomobject]@{ total = 0; healthy = 0; drift = 0 }
      quarantine_counts = [pscustomobject]@{ total = 0; by_activation = [pscustomobject]@{} }
      environment = $Environment
    }
    if ($ExportReportPath) { Write-SafeFoundationDoctorReport $Result $ExportReportPath }
    return $Result
  }

  $FileResults = @()
  foreach ($File in @($State.active_files)) {
    $Path = Resolve-ManagedDestination $File.destination_relative_path $UserProfile
    $Status = if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
      'MISSING'
    } elseif ((Get-Sha256Lower $Path) -cne $File.sha256) {
      'DRIFT'
    } else {
      'HEALTHY'
    }
    $FileResults += [pscustomobject][ordered]@{
      component_id = $File.component_id
      path_id = $File.path_id
      status = $Status
    }
  }
  foreach ($Component in @($State.active_components)) {
    $Root = Resolve-ManagedDestination $Component.destination_relative_path $UserProfile
    $StateFiles = @($State.active_files | Where-Object component_id -CEQ $Component.component_id)
    if (-not (Test-FoundationOwnedTreeExact $Root $StateFiles $UserProfile)) {
      foreach ($FileResult in @($FileResults | Where-Object component_id -CEQ $Component.component_id)) {
        $FileResult.status = 'DRIFT'
      }
    }
  }
  $Components = Merge-FoundationComponentHealth $State.active_components $FileResults
  $Errors = @()
  if (@($FileResults | Where-Object status -ne 'HEALTHY').Count -gt 0) {
    $Errors += 'ACTIVE_DRIFT'
  }
  if ($Pending) { $Errors += 'RECOVERY_REQUIRED' }
  if ($null -ne $Environment) {
    $Compatible = (
      @($State.compatibility.windows) -ccontains [string]$Environment.windows
    ) -and (
      @($State.compatibility.powershell) -ccontains [string]$Environment.powershell
    ) -and (
      @($State.compatibility.codex_versions) -ccontains [string]$Environment.codex_version
    ) -and [bool]$Environment.codex_detected
    if (-not $Compatible) { $Errors += 'UNSUPPORTED_ENVIRONMENT' }
  }
  $Errors = @($Errors | Sort-Object -Unique)
  $HealthyCount = @($Components | Where-Object status -eq 'HEALTHY').Count
  $Result = [pscustomobject][ordered]@{
    healthy = ($Errors.Count -eq 0)
    release_id = $State.release_id
    status = if ($Errors.Count -eq 0) { 'HEALTHY' } else { 'UNHEALTHY' }
    component_results = $Components
    error_codes = $Errors
    active_counts = [pscustomobject][ordered]@{
      total = $Components.Count
      healthy = $HealthyCount
      drift = $Components.Count - $HealthyCount
    }
    quarantine_counts = Get-FoundationQuarantineCounts $State.quarantine_components
    environment = $Environment
  }
  if ($ExportReportPath) { Write-SafeFoundationDoctorReport $Result $ExportReportPath }
  return $Result
}

function Write-SafeFoundationDoctorReport {
  param($DoctorResult, [string]$Path)
  $Environment = if ($null -eq $DoctorResult.environment) {
    [pscustomobject][ordered]@{
      windows = $null
      powershell = $null
      codex_version = $null
      codex_detected = $null
    }
  } else {
    [pscustomobject][ordered]@{
      windows = [string]$DoctorResult.environment.windows
      powershell = [string]$DoctorResult.environment.powershell
      codex_version = [string]$DoctorResult.environment.codex_version
      codex_detected = [bool]$DoctorResult.environment.codex_detected
    }
  }
  $Report = [pscustomobject][ordered]@{
    schema_version = 1
    kind = 'foundation_doctor_safe'
    release_id = $DoctorResult.release_id
    status = $DoctorResult.status
    environment = $Environment
    active_counts = $DoctorResult.active_counts
    quarantine_counts = $DoctorResult.quarantine_counts
    component_results = $DoctorResult.component_results
    error_codes = @($DoctorResult.error_codes)
    generated_at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
  }
  $Parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
  Assert-SafeExistingDirectory $Parent
  Write-CanonicalFoundationJsonExclusive $Report ([IO.Path]::GetFullPath($Path))
}

function Invoke-FoundationInventory {
  param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData
  )
  $Manifest = Read-FoundationManifest (Join-Path $PackageRoot 'release-manifest.json')
  $State = Read-FoundationActiveState $LocalAppData -AllowMissing
  $Rows = @(
    foreach ($Component in @($Manifest.components)) {
      $Health = 'NOT_INSTALLED'
      if ($null -ne $State) {
        if ($Component.activation -ceq 'ACTIVE_ELIGIBLE') {
          $Files = @($State.active_files | Where-Object component_id -CEQ $Component.component_id)
          $Health = if ($Files.Count -gt 0 -and @($Files | Where-Object {
                $Path = Resolve-ManagedDestination $_.destination_relative_path $UserProfile
                -not (Test-Path -LiteralPath $Path -PathType Leaf) -or
                (Get-Sha256Lower $Path) -cne $_.sha256
              }).Count -eq 0) { 'HEALTHY' } else { 'DRIFT' }
        } else {
          $Health = 'EXPECTED_QUARANTINE'
        }
      }
      [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        activation = $Component.activation
        reason = $Component.quarantine_reason
        evidence_ids = @($Component.evidence_ids)
        health = $Health
      }
    }
  )
  return [pscustomobject][ordered]@{
    release_id = $Manifest.release_id
    installed_release_id = if ($State) { $State.release_id } else { $null }
    components = $Rows
  }
}
