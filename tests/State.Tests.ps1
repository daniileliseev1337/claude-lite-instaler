It 'derives target-isolated state roots only from injected LocalAppData' {
  $Root = New-TestRoot 'state-root'
  try {
    $LocalAppData = Join-Path $Root 'local'
    [IO.Directory]::CreateDirectory($LocalAppData) | Out-Null
    foreach ($Target in @('claude', 'codex', 'opencode')) {
      $Expected = [IO.Path]::GetFullPath((Join-Path $LocalAppData "LLMBase\foundation\$Target"))
      Assert-Equal $Expected (Get-FoundationStateRoot $LocalAppData $Target)
      Assert-False (Test-Path -LiteralPath $Expected)
    }
  } finally { Remove-TestRoot $Root }
}

It 'opens one exclusive transaction and blocks a second' {
  $Scenario = New-TestFoundationScenario 'state-journal'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $Context = Open-FoundationTransaction $Plan
    Assert-True (Test-Path -LiteralPath $Context.journal_path)
    Assert-ThrowsCode 'RECOVERY_REQUIRED' { Open-FoundationTransaction $Plan }
  } finally { Remove-TestRoot $Scenario.root }
}
