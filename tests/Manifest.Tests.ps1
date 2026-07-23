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

It 'rejects every non-Codex vendor value' {
  foreach ($Vendor in @('other', 'codex-preview')) {
    $Manifest = Copy-TestManifest
    $Manifest.vendor = $Vendor
    Assert-ThrowsCode 'INVALID_PACKAGE' { Test-FoundationManifest $Manifest }
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
