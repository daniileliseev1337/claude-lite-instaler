function Write-TestJson {
  param($Value, [string]$Path)
  $Json = (ConvertTo-Json $Value -Depth 40).Replace("`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $Json, [Text.UTF8Encoding]::new($false))
}

function New-TestAcceptanceInventory {
  param([string]$SourceRoot, [string]$ReleaseId = 'foundation-fixture-0002')
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
      release_id=$ReleaseId
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

function Get-TestTreeFingerprint {
  param([string]$Root)
  if (-not (Test-Path -LiteralPath $Root)) { return 'ABSENT' }
  $Base = [IO.Path]::GetFullPath($Root)
  $Rows = @()
  foreach ($File in @(Get-ChildItem -LiteralPath $Base -Recurse -File -Force | Sort-Object FullName)) {
    $Relative = $File.FullName.Substring($Base.Length).TrimStart('\').Replace('\','/')
    $Rows += "$Relative|$($File.Length)|$(Get-Sha256Lower $File.FullName)"
  }
  return (Get-FoundationSha256Hex ([Text.UTF8Encoding]::new($false).GetBytes(($Rows -join "`n"))))
}

function New-TestFoundationScenario {
  param([string]$Name = 'scenario')
  $Root = New-TestRoot $Name
  $Source = Join-Path $Root 'approved-source'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\approved-source') `
    -Destination $Source -Recurse
  $InventoryPath = Join-Path $Root 'inventory.json'
  Write-TestJson (New-TestAcceptanceInventory $Source) $InventoryPath
  $PackageRoot = Join-Path $Root 'package'
  $null = New-FoundationPackage $Source $InventoryPath $PackageRoot
  $UserProfile = Join-Path $Root 'user'
  $LocalAppData = Join-Path $Root 'local'
  [IO.Directory]::CreateDirectory($UserProfile) | Out-Null
  [IO.Directory]::CreateDirectory($LocalAppData) | Out-Null
  $Environment = [pscustomobject][ordered]@{
    windows='11'
    powershell='7'
    codex_version='0.145.0-alpha.18'
    codex_detected=$true
  }
  return [pscustomobject]@{
    root=$Root
    source=$Source
    inventory_path=$InventoryPath
    package_root=$PackageRoot
    user_profile=$UserProfile
    local_app_data=$LocalAppData
    environment=$Environment
  }
}

function New-TestUpgradePackage {
  param($Scenario)
  $AgentPath = Join-Path $Scenario.source 'components\agents\auditor.toml'
  [IO.File]::AppendAllText($AgentPath, "version = 2`n", [Text.UTF8Encoding]::new($false))
  $Inventory = New-TestAcceptanceInventory $Scenario.source 'foundation-fixture-0003'
  $Inventory.source_identity.content_sha256 = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  foreach ($Evidence in @($Inventory.evidence)) {
    $Evidence.source_identity = $Inventory.source_identity
  }
  $InventoryPath = Join-Path $Scenario.root 'inventory-b.json'
  Write-TestJson $Inventory $InventoryPath
  $PackageRoot = Join-Path $Scenario.root 'package-b'
  $null = New-FoundationPackage $Scenario.source $InventoryPath $PackageRoot
  return $PackageRoot
}

