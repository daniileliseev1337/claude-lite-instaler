It 'builds the exact active and quarantine package layout' {
  $Root = New-TestRoot 'package-layout'
  try {
    $Source = Join-Path $PSScriptRoot 'fixtures\approved-source'
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson (New-TestAcceptanceInventory $Source) $InventoryPath
    $Output = Join-Path $Root 'package'
    $Result = New-FoundationPackage $Source $InventoryPath $Output
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\core\codex-rules.md'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\agents\auditor.toml'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\metadata\context-budget.json'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'active\metadata\target-manifest.json'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'quarantine\skills\sample-skill\SKILL.md'))
    Assert-True (Test-Path -LiteralPath (Join-Path $Output 'quarantine\mcp\sample-mcp\README.md'))
    Assert-False (Test-Path -LiteralPath (Join-Path $Output 'active\mcp'))
    Assert-Equal 4 $Result.manifest.counts.by_activation.ACTIVE_ELIGIBLE
    Assert-Equal 1 $Result.manifest.counts.by_activation.QUARANTINE_INCOMPATIBLE_VERSION
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

It 'rejects Claude Codex agents and OpenCode live homes as package sources' {
  $Root = New-TestRoot 'package-all-live-homes'
  try {
    foreach ($Relative in @(
        '.claude\source',
        '.codex\source',
        '.agents\source',
        '.opencode\source',
        '.config\opencode\source'
      )) {
      $Unsafe = Join-Path $Root $Relative
      [IO.Directory]::CreateDirectory($Unsafe) | Out-Null
      Assert-ThrowsCode 'BLOCKED_APPROVED_FOUNDATION_SOURCE' {
        Assert-ApprovedSourceRoot $Unsafe
      }
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

It 'rejects a declared source identity after source bytes change' {
  $Root = New-TestRoot 'package-source-binding'
  try {
    $Source = Join-Path $Root 'approved-source'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\approved-source') `
      -Destination $Source -Recurse
    $Inventory = New-TestAcceptanceInventory $Source
    $AgentPath = Join-Path $Source '.codex\agents\auditor.toml'
    [IO.File]::AppendAllText(
      $AgentPath,
      "changed-after-identity`n",
      [Text.UTF8Encoding]::new($false)
    )
    $Digest = Get-FoundationPayloadDigest $AgentPath
    $Component = @(
      $Inventory.components | Where-Object component_id -CEQ 'auditor'
    )[0]
    $Component.sha256 = $Digest.sha256
    $Component.bytes = $Digest.bytes
    $Evidence = @(
      $Inventory.evidence | Where-Object component_id -CEQ 'auditor'
    )[0]
    $Evidence.payload_sha256 = $Digest.sha256
    $InventoryPath = Join-Path $Root 'inventory.json'
    Write-TestJson $Inventory $InventoryPath
    Assert-ThrowsCode 'BLOCKED_APPROVED_FOUNDATION_SOURCE' {
      New-FoundationPackage $Source $InventoryPath (Join-Path $Root 'package')
    }
  } finally { Remove-TestRoot $Root }
}

It 'rejects an active component outside the exact rendered target map' {
  $Root = New-TestRoot 'package-rendered-map-binding'
  try {
    $Source = Join-Path $Root 'approved-source'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\approved-source') `
      -Destination $Source -Recurse
    $ExtraRelative = 'components/agents/auditor-extra.toml'
    $ExtraPath = Join-Path $Source ($ExtraRelative.Replace('/', '\'))
    [IO.Directory]::CreateDirectory((Split-Path -Parent $ExtraPath)) | Out-Null
    [IO.File]::WriteAllText(
      $ExtraPath,
      'extra',
      [Text.UTF8Encoding]::new($false)
    )
    $Inventory = New-TestAcceptanceInventory $Source
    $Digest = Get-FoundationPayloadDigest $ExtraPath
    $Identity = $Inventory.source_identity
    $Inventory.components = @($Inventory.components) + @(
      [pscustomobject][ordered]@{
        component_id='auditor-extra'
        component_type='agent'
        source_relative_path=$ExtraRelative
        destination_relative_path='codex/agents/auditor-extra.toml'
        sha256=$Digest.sha256
        bytes=$Digest.bytes
        dependencies=@()
        acceptance_verdict='PASS'
        evidence_ids=@('evidence-auditor-extra')
        compatible=$true
      }
    )
    $Inventory.evidence = @($Inventory.evidence) + @(
      [pscustomobject][ordered]@{
        evidence_id='evidence-auditor-extra'
        component_id='auditor-extra'
        source_identity=$Identity
        payload_sha256=$Digest.sha256
        verdict='PASS'
      }
    )
    $Inventory.components = @(
      Sort-FoundationObjectsOrdinal $Inventory.components component_id
    )
    $Inventory.evidence = @(
      Sort-FoundationObjectsOrdinal $Inventory.evidence evidence_id
    )
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
