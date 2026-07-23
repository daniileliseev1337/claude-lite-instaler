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
