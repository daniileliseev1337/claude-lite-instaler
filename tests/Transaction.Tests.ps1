It 'installs active files and never copies quarantine into discovery paths' {
  $Scenario = New-TestFoundationScenario 'install-clean'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $Result = Invoke-FoundationInstall $Plan
    Assert-True $Result.installed
    Assert-True (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.codex\AGENTS.md'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.codex\.base\context-budget.json'))
    Assert-False (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.agents\skills\sample-skill'))
    Assert-False (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.codex\mcp'))
    Assert-False (
      Test-PendingFoundationJournal $Scenario.local_app_data `
        $Scenario.environment.target
    )
  } finally { Remove-TestRoot $Scenario.root }
}

It 'leaves a recoverable journal after injected replacement failure' {
  $Scenario = New-TestFoundationScenario 'install-failure'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $Injector = {
      param([string]$Point)
      if ($Point -ceq 'after-replace-1') { throw 'fixture failure' }
    }
    $Caught = $null
    try { Invoke-FoundationInstall $Plan $Injector } catch { $Caught = $_.Exception }
    Assert-True ($null -ne $Caught)
    Assert-True (
      Test-PendingFoundationJournal $Scenario.local_app_data `
        $Scenario.environment.target
    )
    $Rollback = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment.target
    Assert-True $Rollback.rolled_back
    Assert-False (Test-Path -LiteralPath (Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'treats an idempotent reinstall as a verified no-op' {
  $Scenario = New-TestFoundationScenario 'install-idempotent'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $Before = Get-TestTreeFingerprint $Scenario.user_profile
    $Again = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-Equal 4 @($Again.rows | Where-Object action -eq 'UNCHANGED').Count
    $Result = Invoke-FoundationInstall $Again
    Assert-False $Result.installed
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.user_profile)
  } finally { Remove-TestRoot $Scenario.root }
}
