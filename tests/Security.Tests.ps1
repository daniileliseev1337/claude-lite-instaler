function New-TestJunction {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Target
  )
  $null = New-Item -ItemType Junction -Path $Path -Target $Target -ErrorAction Stop
}

function Remove-TestJunction {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    [IO.Directory]::Delete($Path)
  }
}

It 'rejects a reparse point in a managed destination ancestor during plan' {
  $Scenario = New-TestFoundationScenario 'security-plan-reparse'
  $Junction = Join-Path $Scenario.user_profile '.codex'
  try {
    $Outside = Join-Path $Scenario.root 'outside-profile'
    [IO.Directory]::CreateDirectory($Outside) | Out-Null
    New-TestJunction $Junction $Outside
    Assert-ThrowsCode 'UNSAFE_PATH' {
      New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
        $Scenario.local_app_data $Scenario.environment
    }
    Assert-Equal @() @(Get-ChildItem -LiteralPath $Outside -Force)
  } finally {
    Remove-TestJunction $Junction
    Remove-TestRoot $Scenario.root
  }
}

It 'rejects a directory junction anywhere inside a package' {
  $Scenario = New-TestFoundationScenario 'security-package-reparse'
  $Junction = Join-Path $Scenario.package_root 'quarantine\mcp\escape'
  try {
    $Outside = Join-Path $Scenario.root 'outside-package'
    [IO.Directory]::CreateDirectory($Outside) | Out-Null
    [IO.File]::WriteAllText((Join-Path $Outside 'foreign.txt'), 'foreign')
    New-TestJunction $Junction $Outside
    $Manifest = Read-FoundationManifest (
      Join-Path $Scenario.package_root 'release-manifest.json'
    )
    Assert-ThrowsCode 'UNSAFE_PATH' {
      Test-FoundationPackage $Scenario.package_root $Manifest
    }
  } finally {
    Remove-TestJunction $Junction
    Remove-TestRoot $Scenario.root
  }
}

It 'rejects a package payload hash mismatch' {
  $Scenario = New-TestFoundationScenario 'security-package-hash'
  try {
    [IO.File]::AppendAllText(
      (Join-Path $Scenario.package_root 'active\agents\auditor.toml'),
      'tamper'
    )
    $Manifest = Read-FoundationManifest (
      Join-Path $Scenario.package_root 'release-manifest.json'
    )
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      Test-FoundationPackage $Scenario.package_root $Manifest
    }
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects a stale package before opening a transaction' {
  $Scenario = New-TestFoundationScenario 'security-stale-package'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    [IO.File]::AppendAllText(
      (Join-Path $Scenario.package_root 'active\agents\auditor.toml'),
      'tamper'
    )
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      Invoke-FoundationInstall $Plan
    }
    Assert-False (Test-Path -LiteralPath (
      Get-FoundationStateRoot $Scenario.local_app_data $Scenario.environment.target
    ))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects a stale destination before opening a transaction' {
  $Scenario = New-TestFoundationScenario 'security-stale-destination'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $Foreign = Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Foreign)) | Out-Null
    [IO.File]::WriteAllText($Foreign, 'user-owned')
    Assert-ThrowsCode 'USER_CONFLICT' {
      Invoke-FoundationInstall $Plan
    }
    Assert-Equal 'user-owned' ([IO.File]::ReadAllText($Foreign))
    Assert-False (Test-Path -LiteralPath (
      Get-FoundationStateRoot $Scenario.local_app_data $Scenario.environment.target
    ))
  } finally { Remove-TestRoot $Scenario.root }
}

It 'blocks plan and doctor when a pending journal exists' {
  $Scenario = New-TestFoundationScenario 'security-pending-journal'
  try {
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Open-FoundationTransaction $Plan
    $Blocked = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-True $Blocked.blocked
    Assert-True (@($Blocked.blockers.code) -contains 'RECOVERY_REQUIRED')
    $Doctor = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-False $Doctor.healthy
    Assert-True (@($Doctor.error_codes) -contains 'RECOVERY_REQUIRED')
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects a malicious quarantine payload path' {
  $Scenario = New-TestFoundationScenario 'security-quarantine-path'
  try {
    $Manifest = Read-FoundationManifest (
      Join-Path $Scenario.package_root 'release-manifest.json'
    )
    $Mcp = $Manifest.components |
      Where-Object component_id -CEQ 'sample-mcp' |
      Select-Object -First 1
    $Mcp.payload_relative_path = 'quarantine/mcp/../../escape'
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      Test-FoundationManifest $Manifest
    }
  } finally { Remove-TestRoot $Scenario.root }
}

It 'rejects a dependency cycle in the acceptance inventory' {
  $Scenario = New-TestFoundationScenario 'security-dependency-cycle'
  try {
    $Inventory = New-TestAcceptanceInventory $Scenario.source
    $Auditor = $Inventory.components |
      Where-Object component_id -CEQ 'auditor' |
      Select-Object -First 1
    $Auditor.dependencies = @('sample-skill')
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      Resolve-FoundationInventory $Inventory
    }
  } finally { Remove-TestRoot $Scenario.root }
}

It 'does not export seeded config or environment secrets' {
  $Scenario = New-TestFoundationScenario 'security-secret-report'
  try {
    $SecretA = 'SECRET_CONFIG_SIGNATURE_9f1c'
    $SecretB = 'SECRET_ENV_SIGNATURE_2d7a'
    [IO.File]::WriteAllText(
      (Join-Path $Scenario.user_profile 'config.toml'),
      "token=$SecretA"
    )
    $Scenario.environment | Add-Member -NotePropertyName secret_token `
      -NotePropertyValue $SecretB
    $Plan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $Plan
    $Report = Join-Path $Scenario.root 'doctor-safe.json'
    $null = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $Report $Scenario.environment
    $Text = [IO.File]::ReadAllText($Report)
    Assert-False $Text.Contains($SecretA)
    Assert-False $Text.Contains($SecretB)
    Assert-False $Text.Contains($Scenario.user_profile)
    Assert-False $Text.Contains($Scenario.local_app_data)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'bundles without network or external-process commands' {
  $Root = New-TestRoot 'security-bundle-ast'
  try {
    $Bundle = Join-Path $Root 'install.ps1'
    $null = & (Join-Path $PSScriptRoot '..\tools\bundle-installer.ps1') `
      -OutputPath $Bundle
    $Tokens = $null
    $Errors = $null
    $Ast = [Management.Automation.Language.Parser]::ParseFile(
      $Bundle,
      [ref]$Tokens,
      [ref]$Errors
    )
    Assert-Equal 0 @($Errors).Count
    $Commands = @(
      $Ast.FindAll({
          param($Node)
          $Node -is [Management.Automation.Language.CommandAst]
        }, $true) |
        ForEach-Object { $_.GetCommandName() } |
        Where-Object { $null -ne $_ }
    )
    foreach ($Forbidden in @(
        'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer',
        'Start-Process', 'Invoke-Expression', 'iex', 'git', 'curl', 'wget',
        'claude', 'codex', 'opencode'
      )) {
      Assert-False ($Commands -contains $Forbidden) "Forbidden command: $Forbidden"
    }
    Assert-False ([IO.File]::ReadAllText($Bundle) -match '(?i)https?://')
  } finally { Remove-TestRoot $Root }
}

It 'ships a bounded dual-shell synthetic acceptance runner' {
  $Runner = Join-Path $PSScriptRoot '..\tools\run-foundation-acceptance.ps1'
  Assert-True (Test-Path -LiteralPath $Runner -PathType Leaf)
  $Text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Runner))
  Assert-True $Text.Contains('.work\acceptance')
  Assert-True $Text.Contains('pwsh')
  Assert-True $Text.Contains('powershell.exe')
  Assert-True $Text.Contains('synthetic-acceptance-safe.json')
  Assert-True $Text.Contains('FOUNDATION_SYNTHETIC')
  Assert-True $Text.Contains('FULL_RELEASE')
  Assert-False ($Text -match '(?i)Get-ChildItem\s+Env:')
  Assert-False ($Text -match '(?i)\$env:')
}

It 'binds acceptance evidence to one clean committed tree' {
  $Runner = Join-Path $PSScriptRoot '..\tools\run-foundation-acceptance.ps1'
  $Text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Runner))
  Assert-True $Text.Contains('status --porcelain=v1 --untracked-files=all')
  Assert-True $Text.Contains('repo_worktree_clean')
  Assert-True $Text.Contains('repo_tree')
  Assert-True $Text.Contains('DIRTY_ACCEPTANCE_REPO')
}
