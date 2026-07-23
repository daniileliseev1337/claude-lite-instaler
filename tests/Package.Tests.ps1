function Write-TestJson {
  param($Value, [string]$Path)
  $Json = (ConvertTo-Json $Value -Depth 30).Replace("`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $Json, [Text.UTF8Encoding]::new($false))
}

function New-TestAcceptanceInventory {
  param([string]$SourceRoot)
  $AgentPath = Join-Path $SourceRoot 'components\agents\auditor.toml'
  $SkillPath = Join-Path $SourceRoot 'components\skills\sample-skill'
  $McpPath = Join-Path $SourceRoot 'components\mcp\sample-mcp'
  $AgentDigest = Get-FoundationPayloadDigest $AgentPath
  $SkillDigest = Get-FoundationPayloadDigest $SkillPath
  $McpDigest = Get-FoundationPayloadDigest $McpPath
  $Identity = [pscustomobject][ordered]@{
    kind='content-sha256'
    content_sha256='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
  }
  $Components = @(
    [pscustomobject][ordered]@{
      component_id='auditor'
      component_type='agent'
      source_relative_path='components/agents/auditor.toml'
      destination_relative_path='codex/agents/auditor.toml'
      sha256=$AgentDigest.sha256
      bytes=$AgentDigest.bytes
      dependencies=@()
      acceptance_verdict='PASS'
      evidence_ids=@('evidence-agent')
      compatible=$true
    },
    [pscustomobject][ordered]@{
      component_id='sample-mcp'
      component_type='mcp'
      source_relative_path='components/mcp/sample-mcp'
      destination_relative_path=$null
      sha256=$McpDigest.sha256
      bytes=$McpDigest.bytes
      dependencies=@()
      acceptance_verdict='PASS'
      evidence_ids=@('evidence-mcp')
      compatible=$true
    },
    [pscustomobject][ordered]@{
      component_id='sample-skill'
      component_type='skill'
      source_relative_path='components/skills/sample-skill'
      destination_relative_path='agents/skills/sample-skill'
      sha256=$SkillDigest.sha256
      bytes=$SkillDigest.bytes
      dependencies=@('auditor')
      acceptance_verdict='PASS'
      evidence_ids=@('evidence-skill')
      compatible=$true
    }
  )
  $Evidence = @(
    [pscustomobject][ordered]@{
      evidence_id='evidence-agent'
      component_id='auditor'
      source_identity=$Identity
      payload_sha256=$AgentDigest.sha256
      verdict='PASS'
    },
    [pscustomobject][ordered]@{
      evidence_id='evidence-mcp'
      component_id='sample-mcp'
      source_identity=$Identity
      payload_sha256=$McpDigest.sha256
      verdict='PASS'
    },
    [pscustomobject][ordered]@{
      evidence_id='evidence-skill'
      component_id='sample-skill'
      source_identity=$Identity
      payload_sha256=$SkillDigest.sha256
      verdict='PASS'
    }
  )
  return [pscustomobject][ordered]@{
    schema_version=1
    source_identity=$Identity
    environment=[pscustomobject][ordered]@{
      release_id='foundation-fixture-0002'
      built_at_utc='2026-07-23T01:00:00Z'
      installer_protocol_version='1.0.0'
      compatible=$true
      compatibility=[pscustomobject][ordered]@{
        windows=@('10','11')
        powershell=@('5.1','7')
        codex_versions=@('0.145.0-alpha.18')
      }
    }
    components=$Components
    evidence=$Evidence
  }
}

It 'builds the exact active and quarantine package layout' {
  $Root = New-TestRoot 'package-layout'
  try {
    $Source = Join-Path $PSScriptRoot 'fixtures\approved-source'
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson (New-TestAcceptanceInventory $Source) $InventoryPath
    $Output = Join-Path $Root 'package'
    $Result = New-FoundationPackage $Source $InventoryPath $Output
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\agents\auditor.toml'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\skills\sample-skill\SKILL.md'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'quarantine\mcp\sample-mcp\README.md'))
    Assert-False (Test-Path -LiteralPath (Join-Path $Output 'active\mcp'))
    Assert-Equal 2 $Result.manifest.counts.by_activation.ACTIVE_ELIGIBLE
    Assert-Equal 1 $Result.manifest.counts.by_activation.QUARANTINE_UNSUPPORTED_ACTIVATION
  } finally { Remove-TestRoot $Root }
}

It 'builds byte-identical manifests from the same immutable source' {
  $Root = New-TestRoot 'package-determinism'
  try {
    $Source = Join-Path $PSScriptRoot 'fixtures\approved-source'
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson (New-TestAcceptanceInventory $Source) $InventoryPath
    $A = Join-Path $Root 'a'
    $B = Join-Path $Root 'b'
    $null = New-FoundationPackage $Source $InventoryPath $A
    $null = New-FoundationPackage $Source $InventoryPath $B
    Assert-Equal (Get-Sha256Lower (Join-Path $A 'release-manifest.json')) (
      Get-Sha256Lower (Join-Path $B 'release-manifest.json')
    )
  } finally { Remove-TestRoot $Root }
}

It 'rejects a source under a vendor home segment' {
  $Root = New-TestRoot 'package-live-home'
  try {
    $Unsafe = Join-Path $Root '.codex\source'
    [IO.Directory]::CreateDirectory($Unsafe) | Out-Null
    Assert-ThrowsCode 'BLOCKED_APPROVED_FOUNDATION_SOURCE' {
      Assert-ApprovedSourceRoot $Unsafe
    }
  } finally { Remove-TestRoot $Root }
}

It 'rejects evidence bound to a different payload hash' {
  $Root = New-TestRoot 'package-evidence'
  try {
    $Source = Join-Path $PSScriptRoot 'fixtures\approved-source'
    $Inventory = New-TestAcceptanceInventory $Source
    $Inventory.evidence[0].payload_sha256 = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson $Inventory $InventoryPath
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      New-FoundationPackage $Source $InventoryPath (Join-Path $Root 'package')
    }
  } finally { Remove-TestRoot $Root }
}

It 'requires a fresh output root' {
  $Root = New-TestRoot 'package-fresh'
  try {
    $Source = Join-Path $PSScriptRoot 'fixtures\approved-source'
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson (New-TestAcceptanceInventory $Source) $InventoryPath
    $Output = Join-Path $Root 'package'
    [IO.Directory]::CreateDirectory($Output) | Out-Null
    Assert-ThrowsCode 'INVALID_PACKAGE' {
      New-FoundationPackage $Source $InventoryPath $Output
    }
  } finally { Remove-TestRoot $Root }
}

