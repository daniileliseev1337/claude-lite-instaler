function Write-FoundationPlanConsole {
  param($Plan)
  Write-Host "LLM Base Foundation plan"
  Write-Host "Release: $($Plan.release_id)"
  Write-Host "Target: $($Plan.target) | role: $($Plan.install_role)"
  Write-Host "Sync: $($Plan.sync_policy.direction)"
  Write-Host "Blocked: $($Plan.blocked)"
  foreach ($Row in @($Plan.rows)) {
    $Destination = if ($null -eq $Row.destination) { '-' } else { $Row.destination }
    Write-Host ("{0,-16} {1,-18} {2}" -f $Row.action, $Row.component_id, $Destination)
  }
  foreach ($Blocker in @($Plan.blockers)) {
    Write-Host "BLOCKER $($Blocker.code) $($Blocker.component_id) $($Blocker.message)"
  }
}

function Read-FoundationCliRequest {
  param(
    [AllowEmptyCollection()][string[]]$CliArgs,
    [Parameter(Mandatory = $true)]$Environment
  )
  $Command = if (@($CliArgs).Count) {
    $CliArgs[0].ToLowerInvariant()
  } else {
    'plan'
  }
  $Target = [string]$Environment.target
  $Role = if ([string]::IsNullOrWhiteSpace([string]$Environment.install_role)) {
    'consumer'
  } else {
    [string]$Environment.install_role
  }
  $ExportPath = $null
  $SeenOptions = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
  )
  for ($Index = 1; $Index -lt @($CliArgs).Count; $Index++) {
    $Option = [string]$CliArgs[$Index]
    if ($Option -cin @('-Target', '-Role', '-ExportReport')) {
      if (-not $SeenOptions.Add($Option)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' `
          -Message "Duplicate option: $Option"
      }
      if ($Index + 1 -ge $CliArgs.Count) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Missing value for $Option"
      }
      $Value = [string]$CliArgs[$Index + 1]
      $Index++
      switch -CaseSensitive ($Option) {
        '-Target' { $Target = $Value.ToLowerInvariant() }
        '-Role' { $Role = $Value.ToLowerInvariant() }
        '-ExportReport' {
          if ($Command -cne 'doctor') {
            Throw-FoundationError -Code 'INVALID_PACKAGE' -Message '-ExportReport is doctor-only'
          }
          $ExportPath = $Value
        }
      }
    } else {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Unknown option: $Option"
    }
  }
  Assert-FoundationTarget $Target
  Assert-FoundationInstallRole $Role
  return [pscustomobject][ordered]@{
    command = $Command
    target = $Target
    install_role = $Role
    export_report = $ExportPath
  }
}

function New-FoundationCliEnvironment {
  param($Environment, $Request)
  return [pscustomobject][ordered]@{
    target = $Request.target
    install_role = $Request.install_role
    windows = [string]$Environment.windows
    powershell = [string]$Environment.powershell
    client_version = [string]$Environment.client_version
    client_detected = [bool]$Environment.client_detected
  }
}

function Invoke-ConfirmedFoundationInstall {
  param(
    [string]$PackageRoot,
    [string]$UserProfile,
    [string]$LocalAppData,
    $Environment,
    [scriptblock]$ReadConfirmation
  )
  $Plan = New-FoundationPlan $PackageRoot $UserProfile $LocalAppData $Environment
  Write-FoundationPlanConsole $Plan
  if ($Plan.blocked) {
    $Code = [string]$Plan.blockers[0].code
    return Get-FoundationExitCode $Code
  }
  $Expected = "INSTALL $($Plan.release_id) $($Plan.target) $($Plan.install_role)"
  $Prompt = "Type exactly '$Expected' to install"
  $Answer = & $ReadConfirmation $Prompt
  if ([string]$Answer -cne $Expected) {
    Write-Host 'Installation cancelled; no transaction was opened.'
    return 10
  }
  $Result = Invoke-FoundationInstall $Plan
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null $Environment
  if (-not $Doctor.healthy) { return 30 }
  Write-Host (
    "Installed: $($Result.installed) | release: $($Result.release_id) | " +
    "target: $($Plan.target) | role: $($Plan.install_role)"
  )
  return 0
}

function Invoke-FoundationDoctorCli {
  param(
    [string]$UserProfile,
    [string]$LocalAppData,
    $Request,
    $Environment
  )
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData `
    $Request.export_report $Environment
  Write-Host (
    "Doctor: $($Doctor.status) | release: $($Doctor.release_id) | " +
    "target: $($Request.target)"
  )
  foreach ($Code in @($Doctor.error_codes)) { Write-Host "ERROR $Code" }
  if ($Doctor.healthy) { return 0 }
  if (@($Doctor.error_codes) -contains 'RECOVERY_REQUIRED') { return 20 }
  if (@($Doctor.error_codes) -contains 'ACTIVE_DRIFT') { return 30 }
  if (@($Doctor.error_codes) -contains 'UNSUPPORTED_ENVIRONMENT') { return 10 }
  return 30
}

function Invoke-FoundationInventoryCli {
  param(
    [string]$PackageRoot,
    [string]$UserProfile,
    [string]$LocalAppData,
    [string]$Target
  )
  $Manifest = Read-FoundationManifest (Join-Path $PackageRoot 'release-manifest.json')
  if ($Manifest.target -cne $Target) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'CLI target differs from package target'
  }
  $Inventory = Invoke-FoundationInventory $PackageRoot $UserProfile $LocalAppData
  Write-Host "Package release: $($Inventory.release_id)"
  Write-Host "Target: $($Inventory.target)"
  Write-Host "Installed release: $($Inventory.installed_release_id)"
  foreach ($Row in @($Inventory.components)) {
    Write-Host ("{0,-18} {1,-40} {2}" -f $Row.component_type, $Row.component_id, $Row.health)
  }
  return 0
}

function Invoke-FoundationCli {
  param(
    [AllowEmptyCollection()][string[]]$CliArgs,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$UserProfile,
    [Parameter(Mandatory = $true)][string]$LocalAppData,
    [Parameter(Mandatory = $true)]$Environment,
    [scriptblock]$ReadConfirmation = { param($Prompt) Read-Host $Prompt }
  )
  try {
    $Request = Read-FoundationCliRequest $CliArgs $Environment
    $EffectiveEnvironment = New-FoundationCliEnvironment $Environment $Request
    switch ($Request.command) {
      'plan' {
        $Plan = New-FoundationPlan $PackageRoot $UserProfile $LocalAppData `
          $EffectiveEnvironment
        Write-FoundationPlanConsole $Plan
        if ($Plan.blocked) {
          return Get-FoundationExitCode ([string]$Plan.blockers[0].code)
        }
        return 0
      }
      'install' {
        return Invoke-ConfirmedFoundationInstall $PackageRoot $UserProfile `
          $LocalAppData $EffectiveEnvironment $ReadConfirmation
      }
      'doctor' {
        return Invoke-FoundationDoctorCli $UserProfile $LocalAppData $Request `
          $EffectiveEnvironment
      }
      'inventory' {
        return Invoke-FoundationInventoryCli $PackageRoot $UserProfile `
          $LocalAppData $Request.target
      }
      'rollback' {
        $Result = Invoke-FoundationRollback $UserProfile $LocalAppData `
          $Request.target
        Write-Host "Rollback complete | active release: $($Result.release_id)"
        return 0
      }
      default {
        [Console]::Error.WriteLine(
          'Usage: install.ps1 plan|install|doctor|inventory|rollback ' +
          '[-Target claude|codex|opencode] [-Role consumer|hub]'
        )
        return 2
      }
    }
  } catch {
    $Code = [string]$_.Exception.Data['FoundationCode']
    if ([string]::IsNullOrWhiteSpace($Code)) { $Code = 'INVALID_PACKAGE' }
    [Console]::Error.WriteLine("$Code :: $($_.Exception.Message)")
    return Get-FoundationExitCode $Code
  }
}
