It 'plans without changing any filesystem byte' {
  $Scenario = New-TestFoundationScenario 'plan-zero-write'
  try {
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $After = Get-TestTreeFingerprint $Scenario.root
    Assert-Equal $Before $After
    Assert-False $Plan.blocked
    Assert-Equal 2 @($Plan.rows | Where-Object action -eq 'CREATE').Count
    Assert-Equal 1 @($Plan.rows | Where-Object action -eq 'QUARANTINE').Count
    Assert-Equal 3 @($Plan.file_operations).Count
  } finally { Remove-TestRoot $Scenario.root }
}

It 'blocks the whole plan on one foreign destination' {
  $Scenario = New-TestFoundationScenario 'plan-conflict'
  try {
    $Foreign = Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Foreign)) | Out-Null
    [IO.File]::WriteAllText($Foreign, 'user-owned')
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-True $Plan.blocked
    Assert-Equal 'USER_CONFLICT' $Plan.blockers[0].code
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'blocks an unsupported Codex version without writes' {
  $Scenario = New-TestFoundationScenario 'plan-version'
  try {
    $Scenario.environment.codex_version = '9.9.9'
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-True $Plan.blocked
    Assert-Equal 'UNSUPPORTED_ENVIRONMENT' $Plan.blockers[0].code
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
  } finally { Remove-TestRoot $Scenario.root }
}

