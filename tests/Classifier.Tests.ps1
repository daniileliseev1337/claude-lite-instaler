function New-ClassifierComponent {
  param(
    [string]$Verdict = 'PASS',
    [string]$Type = 'skill',
    [bool]$Compatible = $true,
    [string[]]$Dependencies = @(),
    [string[]]$EvidenceIds = @('evidence-1')
  )
  return [pscustomobject]@{
    acceptance_verdict = $Verdict
    component_type = $Type
    compatible = $Compatible
    dependencies = $Dependencies
    evidence_ids = $EvidenceIds
  }
}

$ClassifierCases = @(
  @{ verdict='PASS'; type='skill'; compatible=$true; deps=@(); expected='ACTIVE_ELIGIBLE' },
  @{ verdict='PASS'; type='mcp'; compatible=$true; deps=@(); expected='QUARANTINE_UNSUPPORTED_ACTIVATION' },
  @{ verdict='NOT_TESTED'; type='skill'; compatible=$true; deps=@(); expected='QUARANTINE_NOT_TESTED' },
  @{ verdict='BLOCKED'; type='skill'; compatible=$true; deps=@(); expected='QUARANTINE_BLOCKED' },
  @{ verdict='FAIL'; type='skill'; compatible=$true; deps=@(); expected='QUARANTINE_FAIL' },
  @{ verdict='PASS'; type='skill'; compatible=$false; deps=@(); expected='QUARANTINE_INCOMPATIBLE_VERSION' },
  @{ verdict='PASS'; type='skill'; compatible=$true; deps=@('blocked'); expected='QUARANTINE_DEPENDENCY' }
)

foreach ($Case in $ClassifierCases) {
  It "classifies $($Case.verdict)/$($Case.type) as $($Case.expected)" {
    $Index = @{
      blocked = [pscustomobject]@{ activation = 'QUARANTINE_BLOCKED' }
    }
    $Component = New-ClassifierComponent -Verdict $Case.verdict -Type $Case.type `
      -Compatible $Case.compatible -Dependencies $Case.deps
    $Actual = Resolve-FoundationActivation $Component $Index ([pscustomobject]@{ compatible=$true })
    Assert-Equal $Case.expected $Actual
  }
}

It 'never activates a PASS component without evidence' {
  $Component = New-ClassifierComponent -EvidenceIds @()
  Assert-Equal 'QUARANTINE_NOT_TESTED' (
    Resolve-FoundationActivation $Component @{} ([pscustomobject]@{ compatible=$true })
  )
}

It 'activates a dependency only after its dependency is active' {
  $Component = New-ClassifierComponent -Dependencies @('core')
  $Index = @{ core = [pscustomobject]@{ activation='ACTIVE_ELIGIBLE' } }
  Assert-Equal 'ACTIVE_ELIGIBLE' (
    Resolve-FoundationActivation $Component $Index ([pscustomobject]@{ compatible=$true })
  )
}

