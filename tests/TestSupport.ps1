function Write-TestJson {
  param($Value, [string]$Path)
  $Json = (ConvertTo-Json $Value -Depth 40).Replace("`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $Json, [Text.UTF8Encoding]::new($false))
}

function New-TestAcceptanceInventory {
  param(
    [string]$SourceRoot,
    [string]$ReleaseId = 'foundation-fixture-0002',
    [ValidateSet('claude', 'codex', 'opencode')][string]$Target = 'codex'
  )
  $RenderedMap = Get-FoundationRenderedTargetMap
  $TargetRows = @($RenderedMap.targets.$Target.PSObject.Properties)
  $SkillRelative = 'components/skills/sample-skill'
  $McpRelative = 'components/mcp/sample-mcp'
  $SkillDigest = Get-FoundationPayloadDigest (
    Join-Path $SourceRoot ($SkillRelative.Replace('/', '\'))
  )
  $McpDigest = Get-FoundationPayloadDigest (
    Join-Path $SourceRoot ($McpRelative.Replace('/', '\'))
  )
  $RootDigest = Get-FoundationPayloadDigest $SourceRoot
  $Identity = [pscustomobject][ordered]@{
    kind='content-sha256'
    content_sha256=$RootDigest.sha256
  }
  $SkillDestination = @{
    claude = 'claude/skills/sample-skill'
    codex = 'agents/skills/sample-skill'
    opencode = 'opencode/skills/sample-skill'
  }[$Target]
  $Components = @(
    foreach ($Property in $TargetRows) {
      $Row = $Property.Value
      $SourceRelative = [string]$Property.Name
      $Digest = Get-FoundationPayloadDigest (
        Join-Path $SourceRoot ($SourceRelative.Replace('/', '\'))
      )
      [pscustomobject][ordered]@{
        component_id=[string]$Row.component_id
        component_type=[string]$Row.component_type
        source_relative_path=$SourceRelative
        destination_relative_path=[string]$Row.destination_relative_path
        sha256=$Digest.sha256
        bytes=$Digest.bytes
        dependencies=@()
        acceptance_verdict='PASS'
        evidence_ids=@("evidence-$($Row.component_id)")
        compatible=$true
      }
    }
  ) + @(
    [pscustomobject][ordered]@{
      component_id='sample-mcp'
      component_type='mcp'
      source_relative_path=$McpRelative
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
      source_relative_path=$SkillRelative
      destination_relative_path=$SkillDestination
      sha256=$SkillDigest.sha256
      bytes=$SkillDigest.bytes
      dependencies=@('auditor')
      acceptance_verdict='PASS'
      evidence_ids=@('evidence-skill')
      compatible=$false
    }
  )
  $Evidence = @(
    foreach ($Component in @(
        $Components | Where-Object component_id -notin @(
          'sample-mcp', 'sample-skill'
        )
      )) {
      [pscustomobject][ordered]@{
        evidence_id="evidence-$($Component.component_id)"
        component_id=$Component.component_id
        source_identity=$Identity
        payload_sha256=$Component.sha256
        verdict='PASS'
      }
    }
  ) + @(
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
  $Components = @(Sort-FoundationObjectsOrdinal $Components component_id)
  $Evidence = @(Sort-FoundationObjectsOrdinal $Evidence evidence_id)
  return [pscustomobject][ordered]@{
    schema_version=2
    source_identity=$Identity
    environment=[pscustomobject][ordered]@{
      release_id=$ReleaseId
      built_at_utc='2026-07-23T01:00:00Z'
      installer_protocol_version='1.0.0'
      target=$Target
      compatible=$true
      compatibility=[pscustomobject][ordered]@{
        windows=@('10','11')
        powershell=@('5.1','7')
        client_versions=@('0.145.0-alpha.18')
      }
      sync_policy=[pscustomobject][ordered]@{
        direction='hub-to-consumer'
        default_role='consumer'
        consumer_push=$false
        consumer_feedback_upload=$false
        consumer_session_upload=$false
        credentials_included=$false
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
  param(
    [string]$Name = 'scenario',
    [ValidateSet('claude', 'codex', 'opencode')][string]$Target = 'codex',
    [ValidateSet('consumer', 'hub')][string]$Role = 'consumer'
  )
  $Root = New-TestRoot $Name
  $Source = Join-Path $Root 'approved-source'
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\approved-source') `
    -Destination $Source -Recurse
  $InventoryPath = Join-Path $Root 'inventory.json'
  Write-TestJson (New-TestAcceptanceInventory $Source -Target $Target) $InventoryPath
  $PackageRoot = Join-Path $Root 'package'
  $null = New-FoundationPackage $Source $InventoryPath $PackageRoot
  $UserProfile = Join-Path $Root 'user'
  $LocalAppData = Join-Path $Root 'local'
  [IO.Directory]::CreateDirectory($UserProfile) | Out-Null
  [IO.Directory]::CreateDirectory($LocalAppData) | Out-Null
  $Environment = [pscustomobject][ordered]@{
    target=$Target
    install_role=$Role
    windows='11'
    powershell='7'
    client_version='0.145.0-alpha.18'
    client_detected=$true
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
  $RenderedMap = Get-FoundationRenderedTargetMap
  $AgentRow = @(
    $RenderedMap.targets.$($Scenario.environment.target).PSObject.Properties |
      Where-Object { $_.Value.component_id -ceq 'auditor' }
  )[0]
  $AgentPath = Join-Path $Scenario.source (
    ([string]$AgentRow.Name).Replace('/', '\')
  )
  [IO.File]::AppendAllText($AgentPath, "version = 2`n", [Text.UTF8Encoding]::new($false))
  $Inventory = New-TestAcceptanceInventory $Scenario.source 'foundation-fixture-0003' `
    $Scenario.environment.target
  $InventoryPath = Join-Path $Scenario.root 'inventory-b.json'
  Write-TestJson $Inventory $InventoryPath
  $PackageRoot = Join-Path $Scenario.root 'package-b'
  $null = New-FoundationPackage $Scenario.source $InventoryPath $PackageRoot
  return $PackageRoot
}
