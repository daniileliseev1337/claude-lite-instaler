function ConvertTo-FoundationCanonicalJson {
  param([Parameter(Mandatory = $true)]$Value)
  return (ConvertTo-Json $Value -Depth 100).Replace("`r`n", "`n") + "`n"
}

function Write-CanonicalFoundationJsonExclusive {
  param(
    [Parameter(Mandatory = $true)]$Value,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $Json = ConvertTo-FoundationCanonicalJson $Value
  $Bytes = [Text.UTF8Encoding]::new($false).GetBytes($Json)
  $Stream = [IO.File]::Open(
    $Path,
    [IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write,
    [IO.FileShare]::None
  )
  try {
    $Stream.Write($Bytes, 0, $Bytes.Length)
    $Stream.Flush($true)
  } finally {
    $Stream.Dispose()
  }
  $Reopened = [IO.File]::ReadAllBytes($Path)
  if ($Reopened.Length -ne $Bytes.Length) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Canonical JSON reopen length differs: $Path"
  }
  for ($Index = 0; $Index -lt $Bytes.Length; $Index++) {
    if ($Bytes[$Index] -ne $Reopened[$Index]) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Canonical JSON reopen bytes differ: $Path"
    }
  }
}

function Assert-ApprovedSourceRoot {
  param([Parameter(Mandatory = $true)][string]$SourceRoot)
  $Item = Get-Item -LiteralPath $SourceRoot -Force -ErrorAction Stop
  if (-not $Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Throw-FoundationError -Code 'BLOCKED_APPROVED_FOUNDATION_SOURCE' -Message 'Source root is not a safe directory'
  }
  $Segments = @($Item.FullName -split '[\\/]')
  if (@($Segments | Where-Object { $_ -ieq '.codex' -or $_ -ieq '.claude' }).Count -gt 0) {
    Throw-FoundationError -Code 'BLOCKED_APPROVED_FOUNDATION_SOURCE' -Message 'Live vendor home cannot be package source'
  }
  Assert-SafeExistingDirectory $Item.FullName
  foreach ($Required in @(
    '_package\install.ps1',
    '_package\release-manifest.schema.json',
    '_package\docs\README.md',
    '_package\docs\ROLLBACK.md',
    '_package\docs\QUARANTINE.md'
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $Item.FullName $Required) -PathType Leaf)) {
      Throw-FoundationError -Code 'BLOCKED_APPROVED_FOUNDATION_SOURCE' -Message "Approved source is incomplete: $Required"
    }
  }
}

function New-FoundationSafeDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (Test-Path -LiteralPath $Path) {
    Assert-SafeExistingDirectory $Path
    return
  }
  $Parent = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $Parent)) {
    New-FoundationSafeDirectory $Parent
  }
  Assert-SafeExistingDirectory $Parent
  [IO.Directory]::CreateDirectory($Path) | Out-Null
  Assert-SafeExistingDirectory $Path
}

function Copy-FoundationFileExclusive {
  param([string]$Source, [string]$Target)
  $SourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
  if ($SourceItem.PSIsContainer -or ($SourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Unsafe source file: $Source"
  }
  New-FoundationSafeDirectory (Split-Path -Parent $Target)
  $Input = [IO.File]::Open($SourceItem.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $Output = [IO.File]::Open($Target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try {
    $Input.CopyTo($Output)
    $Output.Flush($true)
  } finally {
    $Output.Dispose()
    $Input.Dispose()
  }
  if ((Get-Sha256Lower $SourceItem.FullName) -cne (Get-Sha256Lower $Target)) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Copied file hash differs: $Target"
  }
}

function Copy-FoundationPayloadExclusive {
  param([string]$Source, [string]$Target)
  $Item = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
  if (-not $Item.PSIsContainer) {
    Copy-FoundationFileExclusive $Item.FullName $Target
    return
  }
  $Digest = Get-FoundationPayloadDigest $Item.FullName
  New-FoundationSafeDirectory $Target
  foreach ($File in @($Digest.files)) {
    $SourceFile = Join-Path $Item.FullName ($File.path.Replace('/', '\'))
    $TargetFile = Join-Path $Target ($File.path.Replace('/', '\'))
    Copy-FoundationFileExclusive $SourceFile $TargetFile
  }
}

function Get-FoundationPackagePayloadPath {
  param($Component)
  $Bucket = if ($Component.activation -ceq 'ACTIVE_ELIGIBLE') { 'active' } else { 'quarantine' }
  switch ([string]$Component.component_type) {
    'core' { return "$Bucket/core/AGENTS.md" }
    'agent' { return "$Bucket/agents/$($Component.component_id).toml" }
    'skill' { return "$Bucket/skills/$($Component.component_id)" }
    'hook' { return "$Bucket/hooks/$($Component.component_id)" }
    'mcp' { return "$Bucket/mcp/$($Component.component_id)" }
    'plugin' { return "$Bucket/plugins/$($Component.component_id)" }
  }
  Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unknown component type'
}

function New-FoundationOrderedCountMap {
  param([object[]]$Components, [string]$Property)
  $Raw = Get-FoundationAggregateMap $Components $Property
  $Ordered = [ordered]@{}
  $Keys = [string[]]@($Raw.Keys)
  [Array]::Sort($Keys, [StringComparer]::Ordinal)
  foreach ($Key in $Keys) { $Ordered[$Key] = [int]$Raw[$Key] }
  return [pscustomobject]$Ordered
}

function Get-FoundationPackageFileRows {
  param([string]$PackageRoot, [object[]]$Components)
  $ComponentByPayload = @{}
  foreach ($Component in $Components) {
    $ComponentByPayload[[string]$Component.payload_relative_path] = [string]$Component.component_id
  }
  $Rows = @()
  $Root = [IO.Path]::GetFullPath($PackageRoot)
  $Pending = [Collections.Generic.Queue[string]]::new()
  $Pending.Enqueue($Root)
  while ($Pending.Count -gt 0) {
    $Directory = $Pending.Dequeue()
    Assert-SafeExistingDirectory $Directory
    foreach ($Child in @(Get-ChildItem -LiteralPath $Directory -Force)) {
      if ($Child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Package contains reparse point: $($Child.FullName)"
      }
      if ($Child.PSIsContainer) {
        $Pending.Enqueue($Child.FullName)
        continue
      }
      $Relative = $Child.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
      if ($Relative -ceq 'release-manifest.json') { continue }
      $Role = if ($Relative -ceq 'install.ps1') {
        'installer'
      } elseif ($Relative -ceq 'release-manifest.schema.json') {
        'schema'
      } elseif ($Relative.StartsWith('docs/', [StringComparison]::Ordinal)) {
        'doc'
      } else {
        'component'
      }
      $ComponentId = $null
      if ($Role -ceq 'component') {
        foreach ($Component in $Components) {
          $Payload = [string]$Component.payload_relative_path
          if ($Relative -ceq $Payload -or $Relative.StartsWith("$Payload/", [StringComparison]::Ordinal)) {
            $ComponentId = [string]$Component.component_id
            break
          }
        }
        if ($null -eq $ComponentId) {
          Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Unowned package payload: $Relative"
        }
      }
      $Rows += [pscustomobject][ordered]@{
        path = $Relative
        role = $Role
        component_id = $ComponentId
        sha256 = Get-Sha256Lower $Child.FullName
        bytes = [int64]$Child.Length
      }
    }
  }
  return @(Sort-FoundationObjectsOrdinal $Rows path)
}

function Test-FoundationPackage {
  param(
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)]$Manifest
  )
  Test-FoundationManifest $Manifest
  Assert-SafeExistingDirectory $PackageRoot
  $Expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $null = $Expected.Add('release-manifest.json')
  foreach ($File in @($Manifest.files)) {
    if (-not $Expected.Add([string]$File.path)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Duplicate package file path'
    }
    $Absolute = Join-Path $PackageRoot (([string]$File.path).Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $Absolute -PathType Leaf)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Package file missing: $($File.path)"
    }
    $Item = Get-Item -LiteralPath $Absolute -Force
    if ([int64]$Item.Length -ne [int64]$File.bytes -or
        (Get-Sha256Lower $Absolute) -cne $File.sha256) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Package file differs: $($File.path)"
    }
  }
  $Actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $Root = [IO.Path]::GetFullPath($PackageRoot)
  foreach ($File in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force)) {
    if ($File.Attributes -band [IO.FileAttributes]::ReparsePoint) {
      Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Package file is a reparse point'
    }
    $Relative = $File.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
    $null = $Actual.Add($Relative)
  }
  if ($Actual.Count -ne $Expected.Count -or @($Actual | Where-Object { -not $Expected.Contains($_) }).Count -gt 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Package contains missing or extra files'
  }
  return [pscustomobject]@{
    valid = $true
    release_id = $Manifest.release_id
    file_count = $Manifest.files.Count
    manifest_sha256 = Get-Sha256Lower (Join-Path $PackageRoot 'release-manifest.json')
  }
}

function New-FoundationPackage {
  param(
    [Parameter(Mandatory = $true)][string]$SourceRoot,
    [Parameter(Mandatory = $true)][string]$InventoryPath,
    [Parameter(Mandatory = $true)][string]$OutputRoot
  )
  Assert-ApprovedSourceRoot $SourceRoot
  if (Test-Path -LiteralPath $OutputRoot) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Package output must be fresh'
  }
  $Inventory = Read-JsonFileStrict $InventoryPath 8388608
  $Classified = Resolve-FoundationInventory $Inventory
  foreach ($Component in @($Classified.components)) {
    $Source = Join-Path $SourceRoot (([string]$Component.source_relative_path).Replace('/', '\'))
    $Digest = Get-FoundationPayloadDigest $Source
    if ($Digest.sha256 -cne $Component.sha256 -or $Digest.bytes -ne [int64]$Component.bytes) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Source hash mismatch: $($Component.component_id)"
    }
  }

  New-FoundationSafeDirectory $OutputRoot
  foreach ($Directory in @(
    'active\core', 'active\agents', 'active\skills',
    'quarantine\agents', 'quarantine\skills', 'quarantine\hooks',
    'quarantine\mcp', 'quarantine\plugins', 'docs'
  )) {
    New-FoundationSafeDirectory (Join-Path $OutputRoot $Directory)
  }
  foreach ($PackageFile in @(
    @{ source='_package\install.ps1'; target='install.ps1' },
    @{ source='_package\release-manifest.schema.json'; target='release-manifest.schema.json' },
    @{ source='_package\docs\README.md'; target='docs\README.md' },
    @{ source='_package\docs\ROLLBACK.md'; target='docs\ROLLBACK.md' },
    @{ source='_package\docs\QUARANTINE.md'; target='docs\QUARANTINE.md' }
  )) {
    Copy-FoundationFileExclusive (Join-Path $SourceRoot $PackageFile.source) `
      (Join-Path $OutputRoot $PackageFile.target)
  }

  $ManifestComponents = @()
  foreach ($Component in @($Classified.components)) {
    $PayloadPath = Get-FoundationPackagePayloadPath $Component
    $Source = Join-Path $SourceRoot (([string]$Component.source_relative_path).Replace('/', '\'))
    $Target = Join-Path $OutputRoot ($PayloadPath.Replace('/', '\'))
    Copy-FoundationPayloadExclusive $Source $Target
    $ManifestComponents += [pscustomobject][ordered]@{
      component_id = $Component.component_id
      component_type = $Component.component_type
      source_identity = $Classified.source_identity
      payload_relative_path = $PayloadPath
      destination_relative_path = if ($Component.activation -ceq 'ACTIVE_ELIGIBLE') {
        $Component.destination_relative_path
      } else { $null }
      sha256 = $Component.sha256
      bytes = [int64]$Component.bytes
      dependencies = @($Component.dependencies)
      acceptance_verdict = $Component.acceptance_verdict
      evidence_ids = @($Component.evidence_ids)
      activation = $Component.activation
      quarantine_reason = $Component.quarantine_reason
    }
  }
  $ManifestComponents = @(Sort-FoundationObjectsOrdinal $ManifestComponents component_id)
  $Files = Get-FoundationPackageFileRows $OutputRoot $ManifestComponents
  $Manifest = [pscustomobject][ordered]@{
    schema_version = 1
    release_id = $Classified.environment.release_id
    channel = 'foundation-canary'
    built_at_utc = $Classified.environment.built_at_utc
    vendor = 'codex'
    source_identity = $Classified.source_identity
    installer_protocol_version = $Classified.environment.installer_protocol_version
    compatibility = $Classified.environment.compatibility
    files = $Files
    components = $ManifestComponents
    counts = [pscustomobject][ordered]@{
      total = $ManifestComponents.Count
      by_type = New-FoundationOrderedCountMap $ManifestComponents 'component_type'
      by_verdict = New-FoundationOrderedCountMap $ManifestComponents 'acceptance_verdict'
      by_activation = New-FoundationOrderedCountMap $ManifestComponents 'activation'
    }
    full_release_verdict = 'NOT_PASS'
  }
  Test-FoundationManifest $Manifest
  Write-CanonicalFoundationJsonExclusive $Manifest (Join-Path $OutputRoot 'release-manifest.json')
  $Verification = Test-FoundationPackage $OutputRoot $Manifest
  return [pscustomobject]@{
    package_root = [IO.Path]::GetFullPath($OutputRoot)
    manifest = $Manifest
    verification = $Verification
  }
}
