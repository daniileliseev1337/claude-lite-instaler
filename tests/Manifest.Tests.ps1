function Copy-TestManifest {
  $Path = Join-Path $PSScriptRoot 'fixtures\manifests\minimal-valid.json'
  return Read-JsonFileStrict $Path 1048576
}

function New-TestComponent {
  param(
    [string]$Id = 'auditor',
    [string]$Type = 'agent',
    [string]$Verdict = 'PASS',
    [string]$Activation = 'ACTIVE_ELIGIBLE',
    [AllowNull()][string]$Destination = 'codex/agents/auditor.toml',
    [AllowNull()][string]$Reason = $null
  )
  return [pscustomobject][ordered]@{
    component_id = $Id
    component_type = $Type
    source_identity = [pscustomobject][ordered]@{
      kind = 'git'
      commit = '1111111111111111111111111111111111111111'
      tree = '2222222222222222222222222222222222222222'
      content_sha256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    }
    payload_relative_path = "active/agents/$Id.toml"
    destination_relative_path = if ([string]::IsNullOrEmpty($Destination)) { $null } else { $Destination }
    sha256 = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    bytes = 5
    dependencies = @()
    acceptance_verdict = $Verdict
    evidence_ids = @('evidence-001')
    activation = $Activation
    quarantine_reason = if ([string]::IsNullOrEmpty($Reason)) { $null } else { $Reason }
  }
}

function Add-TestComponent {
  param($Manifest, $Component)
  $Manifest.components = @($Component)
  $Manifest.files = @(
    [pscustomobject][ordered]@{
      path = $Component.payload_relative_path
      role = 'component'
      component_id = $Component.component_id
      sha256 = $Component.sha256
      bytes = $Component.bytes
    }
  )
  $Manifest.counts = [pscustomobject][ordered]@{
    total = 1
    by_type = [pscustomobject][ordered]@{ $Component.component_type = 1 }
    by_verdict = [pscustomobject][ordered]@{ $Component.acceptance_verdict = 1 }
    by_activation = [pscustomobject][ordered]@{ $Component.activation = 1 }
  }
  return $Manifest
}

It 'accepts the empty closed baseline manifest' {
  $Manifest = Copy-TestManifest
  Test-FoundationManifest $Manifest
}

It 'reads and validates a manifest from disk' {
  $Path = Join-Path $PSScriptRoot 'fixtures\manifests\minimal-valid.json'
  $Manifest = Read-FoundationManifest $Path
  Assert-Equal 'foundation-fixture-0001' $Manifest.release_id
}

It 'accepts one valid active agent component' {
  $Manifest = Add-TestComponent (Copy-TestManifest) (New-TestComponent)
  Test-FoundationManifest $Manifest
}

It 'rejects every non-LLM-base vendor value' {
  foreach ($Vendor in @('other', 'codex', 'llm-base-preview')) {
    $Manifest = Copy-TestManifest
    $Manifest.vendor = $Vendor
    Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
  }
}

It 'accepts exactly Claude Codex and OpenCode targets' {
  foreach ($Target in @('claude', 'codex', 'opencode')) {
    $Manifest = Copy-TestManifest
    $Manifest.target = $Target
    Test-FoundationManifest $Manifest
  }
}

It 'rejects Kimi as a standalone target' {
  $Manifest = Copy-TestManifest
  $Manifest.target = 'kimi'
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'requires a strictly one-way consumer sync policy' {
  foreach ($Property in @(
      'consumer_push', 'consumer_feedback_upload',
      'consumer_session_upload', 'credentials_included'
    )) {
    $Manifest = Copy-TestManifest
    $Manifest.sync_policy.$Property = $true
    Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
  }
  $Manifest = Copy-TestManifest
  $Manifest.sync_policy.direction = 'bidirectional'
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'accepts native active agents for every target and rejects cross-target paths' {
  $Cases = @(
    @{ target='claude'; destination='claude/agents/auditor.md' },
    @{ target='codex'; destination='codex/agents/auditor.toml' },
    @{ target='opencode'; destination='opencode/agents/auditor.md' }
  )
  foreach ($Case in $Cases) {
    $Manifest = Copy-TestManifest
    $Manifest.target = $Case.target
    $Manifest = Add-TestComponent $Manifest (
      New-TestComponent -Destination $Case.destination
    )
    Test-FoundationManifest $Manifest
  }
  $Manifest = Copy-TestManifest
  $Manifest.target = 'opencode'
  $Manifest = Add-TestComponent $Manifest (New-TestComponent)
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'accepts OpenCode core config launcher and metadata components' {
  $Cases = @(
    @{ id='opencode-rules'; type='core'; destination='opencode/AGENTS.md' },
    @{ id='opencode-config'; type='config'; destination='opencode/opencode.json' },
    @{ id='opencode-launcher'; type='launcher'; destination='local/bin/opencode-base.ps1' },
    @{ id='context-budget'; type='metadata'; destination='opencode/.base/context-budget.json' }
  )
  foreach ($Case in $Cases) {
    $Manifest = Copy-TestManifest
    $Manifest.target = 'opencode'
    $Component = New-TestComponent -Id $Case.id -Type $Case.type `
      -Destination $Case.destination
    $Manifest = Add-TestComponent $Manifest $Component
    Test-FoundationManifest $Manifest
  }
}

It 'ships an exact rendered-file map for Claude Codex and OpenCode only' {
  $Path = Join-Path $PSScriptRoot '..\contracts\foundation\rendered-target-map.json'
  $Map = Read-JsonFileStrict $Path 1048576
  Assert-Equal @('schema_version', 'targets') @(
    $Map.PSObject.Properties.Name
  )
  Assert-Equal @('claude', 'codex', 'opencode') @(
    $Map.targets.PSObject.Properties.Name
  )
  foreach ($Target in @('claude', 'codex', 'opencode')) {
    foreach ($Property in @($Map.targets.$Target.PSObject.Properties)) {
      $Row = $Property.Value
      Assert-True (
        Test-FoundationManagedDestinationForComponent $Row $Target
      ) "Invalid rendered target mapping: $Target/$($Property.Name)"
    }
  }
}

It 'rejects an extra top-level property' {
  $Manifest = Copy-TestManifest
  $Manifest | Add-Member -NotePropertyName unexpected -NotePropertyValue $true
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'rejects active MCP hook and plugin components' {
  foreach ($Type in @('mcp', 'hook', 'plugin')) {
    $Component = New-TestComponent -Id "$Type-one" -Type $Type
    $Manifest = Add-TestComponent (Copy-TestManifest) $Component
    Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
  }
}

It 'rejects an active row without evidence' {
  $Component = New-TestComponent
  $Component.evidence_ids = @()
  $Manifest = Add-TestComponent (Copy-TestManifest) $Component
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'rejects a quarantine row with a destination' {
  $Component = New-TestComponent -Verdict 'NOT_TESTED' -Activation 'QUARANTINE_NOT_TESTED' -Reason 'NOT_TESTED'
  $Manifest = Add-TestComponent (Copy-TestManifest) $Component
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'accepts a closed quarantined MCP component' {
  $Component = New-TestComponent -Id 'mcp-one' -Type 'mcp' -Verdict 'PASS' `
    -Activation 'QUARANTINE_UNSUPPORTED_ACTIVATION' -Destination $null `
    -Reason 'UNSUPPORTED_ACTIVATION'
  $Component.payload_relative_path = 'quarantine/mcp/mcp-one'
  $Manifest = Add-TestComponent (Copy-TestManifest) $Component
  Test-FoundationManifest $Manifest
}

It 'rejects count mismatch' {
  $Manifest = Add-TestComponent (Copy-TestManifest) (New-TestComponent)
  $Manifest.counts.total = 2
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'rejects a component source identity different from the release' {
  $Component = New-TestComponent
  $Component.source_identity.tree = '3333333333333333333333333333333333333333'
  $Manifest = Add-TestComponent (Copy-TestManifest) $Component
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'rejects case-insensitive destination collisions' {
  $A = New-TestComponent -Id 'a' -Destination 'codex/agents/a.toml'
  $B = New-TestComponent -Id 'b' -Destination 'codex/agents/A.toml'
  $B.payload_relative_path = 'active/agents/b.toml'
  $B.sha256 = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  $Manifest = Copy-TestManifest
  $Manifest.components = @($A, $B)
  $Manifest.files = @(
    [pscustomobject][ordered]@{ path=$A.payload_relative_path; role='component'; component_id='a'; sha256=$A.sha256; bytes=5 },
    [pscustomobject][ordered]@{ path=$B.payload_relative_path; role='component'; component_id='b'; sha256=$B.sha256; bytes=5 }
  )
  $Manifest.counts = [pscustomobject][ordered]@{
    total=2
    by_type=[pscustomobject][ordered]@{ agent=2 }
    by_verdict=[pscustomobject][ordered]@{ PASS=2 }
    by_activation=[pscustomobject][ordered]@{ ACTIVE_ELIGIBLE=2 }
  }
  Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
}

It 'accepts a content-SHA source identity' {
  $Manifest = Copy-TestManifest
  $Manifest.source_identity = [pscustomobject][ordered]@{
    kind = 'content-sha256'
    content_sha256 = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
  }
  Test-FoundationManifest $Manifest
}
