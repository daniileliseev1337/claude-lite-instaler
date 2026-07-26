It 'restores a clean install to the byte-exact pre-install tree' {
  $Scenario = New-TestFoundationScenario 'rollback-clean'
  try {
    $Before = Get-TestTreeFingerprint $Scenario.user_profile
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $Result = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment.target
    Assert-True $Result.rolled_back
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.user_profile)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'refuses to overwrite a post-install user edit during rollback' {
  $Scenario = New-TestFoundationScenario 'rollback-conflict'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $Agent = Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    [IO.File]::AppendAllText($Agent, 'user edit')
    Assert-ThrowsCode 'ROLLBACK_CONFLICT' {
      Invoke-FoundationRollback $Scenario.user_profile `
        $Scenario.local_app_data $Scenario.environment.target
    }
    Assert-True ([IO.File]::ReadAllText($Agent).Contains('user edit'))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rolls an upgraded release back to the previous healthy release' {
  $Scenario = New-TestFoundationScenario 'rollback-upgrade'
  try {
    $PlanA = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $PlanA
    $Agent = Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    $HashA = Get-Sha256Lower $Agent
    $PackageB = New-TestUpgradePackage $Scenario
    $PlanB = New-FoundationPlan $PackageB $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $PlanB
    Assert-False ((Get-Sha256Lower $Agent) -ceq $HashA)
    $null = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment.target
    Assert-Equal $HashA (Get-Sha256Lower $Agent)
    $Doctor = Invoke-FoundationDoctor $Scenario.user_profile $Scenario.local_app_data $null `
      $Scenario.environment
    Assert-True $Doctor.healthy
    Assert-Equal 'foundation-fixture-0002' $Doctor.release_id
  } finally { Remove-TestRoot $Scenario.root }
}
