function Write-FoundationPlanConsole {
  param($Plan)
  Write-Host "Codex Foundation plan"
  Write-Host "Release: $($Plan.release_id)"
  Write-Host "Blocked: $($Plan.blocked)"
  foreach ($Row in @($Plan.rows)) {
    $Destination = if ($null -eq $Row.destination) { '-' } else { $Row.destination }
    Write-Host ("{0,-16} {1,-18} {2}" -f $Row.action, $Row.component_id, $Destination)
  }
  foreach ($Blocker in @($Plan.blockers)) {
    Write-Host "BLOCKER $($Blocker.code) $($Blocker.component_id) $($Blocker.message)"
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
  $Expected = "INSTALL $($Plan.release_id)"
  $Prompt = "Type exactly '$Expected' to install"
  $Answer = & $ReadConfirmation $Prompt
  if ([string]$Answer -cne $Expected) {
    Write-Host 'Installation cancelled; no transaction was opened.'
    return 10
  }
  $Result = Invoke-FoundationInstall $Plan
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null $Environment
  if (-not $Doctor.healthy) { return 30 }
  Write-Host "Installed: $($Result.installed) | release: $($Result.release_id)"
  return 0
}

function Invoke-FoundationDoctorCli {
  param(
    [string]$UserProfile,
    [string]$LocalAppData,
    [string[]]$CliArgs,
    $Environment
  )
  $ExportPath = $null
  for ($Index = 1; $Index -lt $CliArgs.Count; $Index++) {
    if ($CliArgs[$Index] -ceq '-ExportReport') {
      if ($Index + 1 -ge $CliArgs.Count) { return 2 }
      $ExportPath = $CliArgs[$Index + 1]
      $Index++
    } else {
      return 2
    }
  }
  $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $ExportPath $Environment
  Write-Host "Doctor: $($Doctor.status) | release: $($Doctor.release_id)"
  foreach ($Code in @($Doctor.error_codes)) { Write-Host "ERROR $Code" }
  if ($Doctor.healthy) { return 0 }
  if (@($Doctor.error_codes) -contains 'RECOVERY_REQUIRED') { return 20 }
  if (@($Doctor.error_codes) -contains 'ACTIVE_DRIFT') { return 30 }
  if (@($Doctor.error_codes) -contains 'UNSUPPORTED_ENVIRONMENT') { return 10 }
  return 30
}

function Invoke-FoundationInventoryCli {
  param([string]$PackageRoot, [string]$UserProfile, [string]$LocalAppData)
  $Inventory = Invoke-FoundationInventory $PackageRoot $UserProfile $LocalAppData
  Write-Host "Package release: $($Inventory.release_id)"
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
  $Command = if (@($CliArgs).Count) { $CliArgs[0].ToLowerInvariant() } else { 'plan' }
  try {
    switch ($Command) {
      'plan' {
        if (@($CliArgs).Count -gt 1) { return 2 }
        $Plan = New-FoundationPlan $PackageRoot $UserProfile $LocalAppData $Environment
        Write-FoundationPlanConsole $Plan
        if ($Plan.blocked) { return Get-FoundationExitCode ([string]$Plan.blockers[0].code) }
        return 0
      }
      'install' {
        if (@($CliArgs).Count -gt 1) { return 2 }
        return Invoke-ConfirmedFoundationInstall $PackageRoot $UserProfile `
          $LocalAppData $Environment $ReadConfirmation
      }
      'doctor' {
        return Invoke-FoundationDoctorCli $UserProfile $LocalAppData $CliArgs $Environment
      }
      'inventory' {
        if (@($CliArgs).Count -gt 1) { return 2 }
        return Invoke-FoundationInventoryCli $PackageRoot $UserProfile $LocalAppData
      }
      'rollback' {
        if (@($CliArgs).Count -gt 1) { return 2 }
        $Result = Invoke-FoundationRollback $UserProfile $LocalAppData
        Write-Host "Rollback complete | active release: $($Result.release_id)"
        return 0
      }
      default {
        [Console]::Error.WriteLine('Usage: install.ps1 plan|install|doctor|inventory|rollback')
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
