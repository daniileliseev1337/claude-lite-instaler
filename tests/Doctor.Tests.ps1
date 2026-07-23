It 'reports a healthy installed release with expected quarantine' {
  $Scenario = New-TestFoundationScenario 'doctor-healthy'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $Doctor = Invoke-FoundationDoctor $Scenario.user_profile $Scenario.local_app_data $null `
      $Scenario.environment
    Assert-True $Doctor.healthy
    Assert-Equal 1 $Doctor.quarantine_counts.total
    Assert-Equal @() @($Doctor.error_codes)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'detects active drift without repairing it' {
  $Scenario = New-TestFoundationScenario 'doctor-drift'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    [IO.File]::AppendAllText(
      (Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'),
      'drift'
    )
    $Doctor = Invoke-FoundationDoctor $Scenario.user_profile $Scenario.local_app_data $null `
      $Scenario.environment
    Assert-False $Doctor.healthy
    Assert-Equal 'ACTIVE_DRIFT' $Doctor.error_codes[0]
  } finally { Remove-TestRoot $Scenario.root }
}

It 'exports a bounded safe report without seeded secret strings' {
  $Scenario = New-TestFoundationScenario 'doctor-report'
  try {
    $Secret = 'SECRET_DO_NOT_EXPORT_123'
    [IO.File]::WriteAllText((Join-Path $Scenario.user_profile 'config.toml'), "token=$Secret")
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $ReportPath = Join-Path $Scenario.root 'doctor-safe.json'
    $null = Invoke-FoundationDoctor $Scenario.user_profile $Scenario.local_app_data `
      $ReportPath $Scenario.environment
    $ReportBytes = [IO.File]::ReadAllText($ReportPath)
    Assert-False $ReportBytes.Contains($Secret)
    $Report = Read-JsonFileStrict $ReportPath 1048576
    Assert-Equal @(
      'active_counts','component_results','environment','error_codes',
      'generated_at_utc','kind','quarantine_counts','release_id',
      'schema_version','status'
    ) @($Report.PSObject.Properties.Name | Sort-Object)
  } finally { Remove-TestRoot $Scenario.root }
}

