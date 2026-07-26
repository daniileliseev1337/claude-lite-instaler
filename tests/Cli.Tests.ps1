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
      { param($Prompt) 'INSTALL foundation-fixture-0002 codex consumer' }
    Assert-Equal 0 $Code
    Assert-True (Test-Path -LiteralPath (
      Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    ))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'accepts explicit matching target and hub role and records them' {
  $Scenario = New-TestFoundationScenario 'cli-target-role' -Role hub
  try {
    $Code = Invoke-FoundationCli @(
      'install', '-Target', 'codex', '-Role', 'hub'
    ) $Scenario.package_root $Scenario.user_profile $Scenario.local_app_data `
      $Scenario.environment {
        param($Prompt)
        'INSTALL foundation-fixture-0002 codex hub'
      }
    Assert-Equal 0 $Code
    $State = Read-FoundationActiveState $Scenario.local_app_data codex
    Assert-Equal 'codex' $State.target
    Assert-Equal 'hub' $State.install_role
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects Kimi in the target CLI option without writes' {
  $Scenario = New-TestFoundationScenario 'cli-kimi'
  try {
    $Before = Get-TestTreeFingerprint $Scenario.root
    $Code = Invoke-FoundationCli @('plan', '-Target', 'kimi') `
      $Scenario.package_root $Scenario.user_profile $Scenario.local_app_data `
      $Scenario.environment
    Assert-Equal 2 $Code
    Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects duplicate target or role options without writes' {
  $Scenario = New-TestFoundationScenario 'cli-duplicate-option'
  try {
    foreach ($Args in @(
        @('plan', '-Target', 'codex', '-Target', 'opencode'),
        @('plan', '-Role', 'consumer', '-Role', 'hub')
      )) {
      $Before = Get-TestTreeFingerprint $Scenario.root
      $Code = Invoke-FoundationCli $Args $Scenario.package_root `
        $Scenario.user_profile $Scenario.local_app_data $Scenario.environment
      Assert-Equal 2 $Code
      Assert-Equal $Before (Get-TestTreeFingerprint $Scenario.root)
    }
  } finally { Remove-TestRoot $Scenario.root }
}

It 'installs isolated target packages side by side' {
  $Root = New-TestRoot 'cli-multi-target'
  try {
    $User = Join-Path $Root 'user'
    $Local = Join-Path $Root 'local'
    [IO.Directory]::CreateDirectory($User) | Out-Null
    [IO.Directory]::CreateDirectory($Local) | Out-Null
    foreach ($Target in @('claude', 'codex', 'opencode')) {
      $Scenario = New-TestFoundationScenario "nested-$Target" -Target $Target
      $Scenario.user_profile = $User
      $Scenario.local_app_data = $Local
      $Code = Invoke-FoundationCli @('install') $Scenario.package_root $User $Local `
        $Scenario.environment {
          param($Prompt)
          "INSTALL foundation-fixture-0002 $Target consumer"
        }
      Assert-Equal 0 $Code
      $State = Read-FoundationActiveState $Local $Target
      Assert-Equal $Target $State.target
      Remove-TestRoot $Scenario.root
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $User '.claude\agents\auditor.md'))
    Assert-True (Test-Path -LiteralPath (Join-Path $User '.codex\agents\auditor.toml'))
    Assert-True (Test-Path -LiteralPath (Join-Path $User '.config\opencode\agents\auditor.md'))
  } finally { Remove-TestRoot $Root }
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
      'Start-Process','git','curl','wget','claude','codex','opencode'
    )) {
      Assert-False ($Commands -contains $Forbidden) "Forbidden runtime command: $Forbidden"
    }
  } finally { Remove-TestRoot $Root }
}
