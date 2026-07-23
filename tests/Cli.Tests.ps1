It 'uses plan as the default zero-write command' {
  $Scenario = New-TestFoundationScenario 'cli-default'
  try {
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Code = Invoke-FoundationCli @() $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-Equal 0 $Code
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'returns usage code for an unknown command' {
  $Scenario = New-TestFoundationScenario 'cli-usage'
  try {
    $Code = Invoke-FoundationCli @('unknown') $Scenario.package_root `
      $Scenario.user_profile $Scenario.local_app_data $Scenario.environment
    Assert-Equal 2 $Code
  } finally { Remove-TestRoot $Scenario.root }
}

It 'denies install without the exact visible confirmation' {
  $Scenario = New-TestFoundationScenario 'cli-deny'
  try {
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Code = Invoke-FoundationCli @('install') $Scenario.package_root `
      $Scenario.user_profile $Scenario.local_app_data $Scenario.environment { 'NO' }
    Assert-Equal 10 $Code
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'installs after the exact release confirmation' {
  $Scenario = New-TestFoundationScenario 'cli-install'
  try {
    $Code = Invoke-FoundationCli @('install') $Scenario.package_root `
      $Scenario.user_profile $Scenario.local_app_data $Scenario.environment `
      { param($Prompt) 'INSTALL foundation-fixture-0002' }
    Assert-Equal 0 $Code
    Assert-True (Test-Path -LiteralPath (
      Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    ))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'maps doctor drift to exit code 30' {
  $Scenario = New-TestFoundationScenario 'cli-doctor'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    [IO.File]::AppendAllText(
      (Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'),
      'drift'
    )
    $Code = Invoke-FoundationCli @('doctor') $Scenario.package_root `
      $Scenario.user_profile $Scenario.local_app_data $Scenario.environment
    Assert-Equal 30 $Code
  } finally { Remove-TestRoot $Scenario.root }
}

It 'builds one byte-identical self-contained installer twice' {
  $Root = New-TestRoot 'bundle'
  try {
    $Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $Tool = Join-Path $Repo 'tools\bundle-installer.ps1'
    $A = Join-Path $Root 'install-a.ps1'
    $B = Join-Path $Root 'install-b.ps1'
    $null = & $Tool -OutputPath $A
    $null = & $Tool -OutputPath $B
    Assert-Equal (Get-Sha256Lower $A) (Get-Sha256Lower $B)
    $Tokens = $null
    $Errors = $null
    $Ast = [Management.Automation.Language.Parser]::ParseFile(
      $A,
      [ref]$Tokens,
      [ref]$Errors
    )
    Assert-Equal 0 @($Errors).Count
    $Commands = @(
      $Ast.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.CommandAst]
      }, $true) | ForEach-Object { $_.GetCommandName() }
    )
    foreach ($Forbidden in @(
      'Invoke-WebRequest','Invoke-RestMethod','Start-BitsTransfer',
      'Start-Process','git','curl','wget','codex'
    )) {
      Assert-False ($Commands -contains $Forbidden) "Forbidden runtime command: $Forbidden"
    }
  } finally { Remove-TestRoot $Root }
}
