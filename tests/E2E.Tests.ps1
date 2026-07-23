It 'completes the full fake-home install upgrade drift and rollback lifecycle' {
  $Scenario = New-TestFoundationScenario 'e2e-lifecycle'
  try {
    $CodexUserFile = Join-Path $Scenario.user_profile '.codex\user-notes.txt'
    $AgentsUserFile = Join-Path $Scenario.user_profile '.agents\personal.bin'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $CodexUserFile)) | Out-Null
    [IO.Directory]::CreateDirectory((Split-Path -Parent $AgentsUserFile)) | Out-Null
    [IO.File]::WriteAllText($CodexUserFile, 'user-owned-codex')
    [IO.File]::WriteAllBytes($AgentsUserFile, [byte[]](0, 1, 2, 254, 255))
    $PreA = Get-TestTreeFingerprint $Scenario.user_profile
    $CodexUserHash = Get-Sha256Lower $CodexUserFile
    $AgentsUserHash = Get-Sha256Lower $AgentsUserFile

    $PlanA = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-False $PlanA.blocked
    $InstallA = Invoke-FoundationInstall $PlanA
    Assert-True $InstallA.installed
    $DoctorA = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-True $DoctorA.healthy
    Assert-Equal 'foundation-fixture-0002' $DoctorA.release_id
    $InventoryA = Invoke-FoundationInventory $Scenario.package_root `
      $Scenario.user_profile $Scenario.local_app_data
    Assert-Equal 2 @(
      $InventoryA.components | Where-Object health -CEQ 'HEALTHY'
    ).Count
    Assert-Equal 1 @(
      $InventoryA.components | Where-Object health -CEQ 'EXPECTED_QUARANTINE'
    ).Count

    $NoOpPlan = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $NoOp = Invoke-FoundationInstall $NoOpPlan
    Assert-False $NoOp.installed

    $null = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data
    Assert-Equal $PreA (Get-TestTreeFingerprint $Scenario.user_profile)

    $PlanA2 = New-FoundationPlan $Scenario.package_root $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    $null = Invoke-FoundationInstall $PlanA2
    $Agent = Join-Path $Scenario.user_profile '.codex\agents\auditor.toml'
    $AgentHashA = Get-Sha256Lower $Agent

    $PackageB = New-TestUpgradePackage $Scenario
    $PlanB = New-FoundationPlan $PackageB $Scenario.user_profile `
      $Scenario.local_app_data $Scenario.environment
    Assert-False $PlanB.blocked
    Assert-True (@($PlanB.rows.action) -contains 'MANAGED_UPDATE')
    $null = Invoke-FoundationInstall $PlanB
    $DoctorB = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-True $DoctorB.healthy
    Assert-Equal 'foundation-fixture-0003' $DoctorB.release_id

    $ExpectedB = Join-Path $PackageB 'active\agents\auditor.toml'
    [IO.File]::AppendAllText($Agent, 'drift')
    $Drifted = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-False $Drifted.healthy
    Assert-True (@($Drifted.error_codes) -contains 'ACTIVE_DRIFT')
    [IO.File]::Copy($ExpectedB, $Agent, $true)
    $RestoredB = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-True $RestoredB.healthy

    $null = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data
    $BackToA = Invoke-FoundationDoctor $Scenario.user_profile `
      $Scenario.local_app_data $null $Scenario.environment
    Assert-True $BackToA.healthy
    Assert-Equal 'foundation-fixture-0002' $BackToA.release_id
    Assert-Equal $AgentHashA (Get-Sha256Lower $Agent)
    Assert-Equal $CodexUserHash (Get-Sha256Lower $CodexUserFile)
    Assert-Equal $AgentsUserHash (Get-Sha256Lower $AgentsUserFile)

    $null = Invoke-FoundationRollback $Scenario.user_profile `
      $Scenario.local_app_data
    Assert-Equal $PreA (Get-TestTreeFingerprint $Scenario.user_profile)
  } finally { Remove-TestRoot $Scenario.root }
}

It 'recovers every exposed transaction failure point without unexplained change' {
  $Scenario = New-TestFoundationScenario 'e2e-failure-matrix'
  try {
    $Points = @(
      'after-snapshot',
      'after-stage-1', 'after-replace-1',
      'after-stage-2', 'after-replace-2',
      'after-stage-3', 'after-replace-3',
      'before-doctor', 'after-doctor',
      'before-state', 'after-state',
      'before-close'
    )
    $Ordinal = 0
    foreach ($FailurePoint in $Points) {
      $Ordinal++
      $CaseRoot = Join-Path $Scenario.root ("failure-{0:D2}" -f $Ordinal)
      $UserProfile = Join-Path $CaseRoot 'user'
      $LocalAppData = Join-Path $CaseRoot 'local'
      [IO.Directory]::CreateDirectory($UserProfile) | Out-Null
      [IO.Directory]::CreateDirectory($LocalAppData) | Out-Null
      $Marker = Join-Path $UserProfile 'user-owned.txt'
      [IO.File]::WriteAllText($Marker, "marker-$Ordinal")
      $Before = Get-TestTreeFingerprint $UserProfile
      $Plan = New-FoundationPlan $Scenario.package_root $UserProfile `
        $LocalAppData $Scenario.environment
      $PointToFail = $FailurePoint
      $Injector = {
        param([string]$Point)
        if ($Point -ceq $PointToFail) {
          throw "injected:$Point"
        }
      }
      $Caught = $null
      try {
        $null = Invoke-FoundationInstall $Plan $Injector
      } catch {
        $Caught = $_.Exception
      }
      Assert-True ($null -ne $Caught) "Failure point did not fire: $FailurePoint"
      Assert-True (Test-PendingFoundationJournal $LocalAppData) `
        "Journal missing after: $FailurePoint"
      $null = Invoke-FoundationRollback $UserProfile $LocalAppData
      Assert-False (Test-PendingFoundationJournal $LocalAppData)
      Assert-Equal $Before (Get-TestTreeFingerprint $UserProfile) `
        "Unexplained profile change after: $FailurePoint"
      Assert-Equal 0 @(
        Get-ChildItem -LiteralPath $UserProfile -Recurse -File -Force |
          Where-Object Name -like '*.foundation-*.tmp'
      ).Count "Staging residue after: $FailurePoint"
      $Doctor = Invoke-FoundationDoctor $UserProfile $LocalAppData $null `
        $Scenario.environment
      Assert-True $Doctor.healthy
      Assert-Equal 'NOT_INSTALLED' $Doctor.status
    }
  } finally { Remove-TestRoot $Scenario.root }
}
