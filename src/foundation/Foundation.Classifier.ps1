function Resolve-FoundationActivation {
  param(
    [Parameter(Mandatory = $true)]$Component,
    [Parameter(Mandatory = $true)]$ComponentIndex,
    [Parameter(Mandatory = $true)]$Environment
  )
  if ($Component.acceptance_verdict -ceq 'FAIL') { return 'QUARANTINE_FAIL' }
  if ($Component.acceptance_verdict -ceq 'BLOCKED') { return 'QUARANTINE_BLOCKED' }
  if ($Component.acceptance_verdict -cne 'PASS' -or @($Component.evidence_ids).Count -eq 0) {
    return 'QUARANTINE_NOT_TESTED'
  }
  if (@('core', 'agent', 'skill') -cnotcontains [string]$Component.component_type) {
    return 'QUARANTINE_UNSUPPORTED_ACTIVATION'
  }
  if (-not [bool]$Environment.compatible -or -not [bool]$Component.compatible) {
    return 'QUARANTINE_INCOMPATIBLE_VERSION'
  }
  foreach ($Dependency in @($Component.dependencies)) {
    if (-not $ComponentIndex.ContainsKey([string]$Dependency) -or
        $ComponentIndex[[string]$Dependency].activation -cne 'ACTIVE_ELIGIBLE') {
      return 'QUARANTINE_DEPENDENCY'
    }
  }
  return 'ACTIVE_ELIGIBLE'
}

function Get-FoundationQuarantineReason {
  param([string]$Activation)
  return @{
    QUARANTINE_NOT_TESTED = 'NOT_TESTED'
    QUARANTINE_BLOCKED = 'BLOCKED'
    QUARANTINE_FAIL = 'FAIL'
    QUARANTINE_DEPENDENCY = 'DEPENDENCY'
    QUARANTINE_UNSUPPORTED_ACTIVATION = 'UNSUPPORTED_ACTIVATION'
    QUARANTINE_INCOMPATIBLE_VERSION = 'INCOMPATIBLE_VERSION'
  }[$Activation]
}

function Test-AcceptanceInventory {
  param([Parameter(Mandatory = $true)]$Inventory)
  Assert-ExactProperties $Inventory @(
    'schema_version', 'source_identity', 'environment', 'components', 'evidence'
  ) 'acceptance inventory'
  if ($Inventory.schema_version -ne 1) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Acceptance schema version differs'
  }
  $SourceKey = Get-FoundationSourceIdentityKey $Inventory.source_identity
  Assert-ExactProperties $Inventory.environment @(
    'release_id', 'built_at_utc', 'installer_protocol_version', 'compatible', 'compatibility'
  ) 'acceptance environment'
  if ($Inventory.environment.release_id -notmatch '^foundation-[a-z0-9][a-z0-9.-]{0,79}$' -or
      $Inventory.environment.built_at_utc -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' -or
      $Inventory.environment.installer_protocol_version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$' -or
      $Inventory.environment.compatible -isnot [bool]) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid acceptance environment'
  }
  Assert-ExactProperties $Inventory.environment.compatibility @(
    'windows', 'powershell', 'codex_versions'
  ) 'acceptance compatibility'
  Assert-FoundationStringArray @($Inventory.environment.compatibility.windows) `
    'acceptance compatibility.windows' -Allowed @('10', '11')
  Assert-FoundationStringArray @($Inventory.environment.compatibility.powershell) `
    'acceptance compatibility.powershell' -Allowed @('5.1', '7')
  Assert-FoundationStringArray @($Inventory.environment.compatibility.codex_versions) `
    'acceptance compatibility.codex_versions'

  $Components = @{}
  $CaseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $Previous = $null
  foreach ($Component in @($Inventory.components)) {
    Assert-ExactProperties $Component @(
      'component_id', 'component_type', 'source_relative_path',
      'destination_relative_path', 'sha256', 'bytes', 'dependencies',
      'acceptance_verdict', 'evidence_ids', 'compatible'
    ) 'acceptance component'
    if ($Component.component_id -notmatch '^[a-z0-9][a-z0-9._-]{0,99}$' -or
        -not $CaseIds.Add([string]$Component.component_id) -or
        ($null -ne $Previous -and
          [StringComparer]::Ordinal.Compare($Previous, [string]$Component.component_id) -ge 0) -or
        @('core', 'agent', 'skill', 'hook', 'mcp', 'plugin') -cnotcontains [string]$Component.component_type -or
        @('PASS', 'NOT_TESTED', 'BLOCKED', 'FAIL') -cnotcontains [string]$Component.acceptance_verdict -or
        -not (Test-PortableRelativePath ([string]$Component.source_relative_path)) -or
        -not ([string]$Component.source_relative_path).StartsWith('components/', [StringComparison]::Ordinal) -or
        $Component.sha256 -notmatch '^[0-9a-f]{64}$' -or
        ($Component.bytes -isnot [int] -and $Component.bytes -isnot [long]) -or
        [int64]$Component.bytes -lt 0 -or $Component.compatible -isnot [bool]) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid acceptance component'
    }
    $Previous = [string]$Component.component_id
    Assert-FoundationStringArray @($Component.dependencies) 'acceptance dependencies' -AllowEmpty
    Assert-FoundationStringArray @($Component.evidence_ids) 'acceptance evidence IDs' -AllowEmpty
    $Components[[string]$Component.component_id] = $Component
  }
  foreach ($Component in @($Inventory.components)) {
    foreach ($Dependency in @($Component.dependencies)) {
      if ($Dependency -ceq $Component.component_id -or -not $Components.ContainsKey([string]$Dependency)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Missing or self acceptance dependency'
      }
    }
  }

  $Evidence = @{}
  $PreviousEvidence = $null
  foreach ($Row in @($Inventory.evidence)) {
    Assert-ExactProperties $Row @(
      'evidence_id', 'component_id', 'source_identity', 'payload_sha256', 'verdict'
    ) 'acceptance evidence'
    if ($Row.evidence_id -notmatch '^[a-z0-9][a-z0-9._-]{0,127}$' -or
        $Evidence.ContainsKey([string]$Row.evidence_id) -or
        ($null -ne $PreviousEvidence -and
          [StringComparer]::Ordinal.Compare($PreviousEvidence, [string]$Row.evidence_id) -ge 0) -or
        -not $Components.ContainsKey([string]$Row.component_id) -or
        (Get-FoundationSourceIdentityKey $Row.source_identity) -cne $SourceKey -or
        $Row.payload_sha256 -notmatch '^[0-9a-f]{64}$' -or
        @('PASS', 'NOT_TESTED', 'BLOCKED', 'FAIL') -cnotcontains [string]$Row.verdict) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid acceptance evidence'
    }
    $PreviousEvidence = [string]$Row.evidence_id
    $Evidence[[string]$Row.evidence_id] = $Row
  }
  foreach ($Component in @($Inventory.components)) {
    foreach ($EvidenceId in @($Component.evidence_ids)) {
      if (-not $Evidence.ContainsKey([string]$EvidenceId)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Missing evidence row'
      }
      $Row = $Evidence[[string]$EvidenceId]
      if ($Row.component_id -cne $Component.component_id -or
          $Row.payload_sha256 -cne $Component.sha256 -or
          $Row.verdict -cne $Component.acceptance_verdict) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Evidence binding differs'
      }
    }
  }
}

function Resolve-FoundationInventory {
  param([Parameter(Mandatory = $true)]$Inventory)
  Test-AcceptanceInventory $Inventory
  $Remaining = @{}
  foreach ($Component in @($Inventory.components)) {
    $Remaining[[string]$Component.component_id] = $Component
  }
  $Index = @{}
  $Resolved = @()
  while ($Remaining.Count -gt 0) {
    $Candidates = @(
      $Remaining.Values |
        Where-Object {
          $Candidate = $_
          @($Candidate.dependencies | Where-Object { -not $Index.ContainsKey([string]$_) }).Count -eq 0
        }
    )
    $Ready = @(Sort-FoundationObjectsOrdinal $Candidates component_id)
    if ($Ready.Count -eq 0) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Dependency cycle in acceptance inventory'
    }
    foreach ($Component in $Ready) {
      $Activation = Resolve-FoundationActivation $Component $Index $Inventory.environment
      $Classified = [pscustomobject][ordered]@{
        component_id = $Component.component_id
        component_type = $Component.component_type
        source_relative_path = $Component.source_relative_path
        destination_relative_path = $Component.destination_relative_path
        sha256 = $Component.sha256
        bytes = [int64]$Component.bytes
        dependencies = @($Component.dependencies)
        acceptance_verdict = $Component.acceptance_verdict
        evidence_ids = @($Component.evidence_ids)
        compatible = [bool]$Component.compatible
        activation = $Activation
        quarantine_reason = if ($Activation -ceq 'ACTIVE_ELIGIBLE') {
          $null
        } else {
          Get-FoundationQuarantineReason $Activation
        }
      }
      $Index[[string]$Component.component_id] = $Classified
      $Resolved += $Classified
      $Remaining.Remove([string]$Component.component_id)
    }
  }
  return [pscustomobject][ordered]@{
    schema_version = $Inventory.schema_version
    source_identity = $Inventory.source_identity
    environment = $Inventory.environment
    components = @(Sort-FoundationObjectsOrdinal $Resolved component_id)
    evidence = @($Inventory.evidence)
  }
}
