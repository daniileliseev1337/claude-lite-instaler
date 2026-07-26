function Read-FoundationManifest {
  param([Parameter(Mandatory = $true)][string]$Path)
  $Manifest = Read-JsonFileStrict $Path 4194304
  Test-FoundationManifest $Manifest
  return $Manifest
}

function Assert-FoundationSourceIdentity {
  param([Parameter(Mandatory = $true)]$Identity)
  if ($null -eq $Identity -or $Identity -isnot [Management.Automation.PSCustomObject]) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'source_identity must be an object'
  }
  if ($Identity.kind -ceq 'git') {
    Assert-ExactProperties $Identity @(
      'kind', 'commit', 'tree', 'content_sha256'
    ) 'source_identity'
    if ($Identity.commit -notmatch '^[0-9a-f]{40}$' -or
        $Identity.tree -notmatch '^[0-9a-f]{40}$' -or
        $Identity.content_sha256 -notmatch '^[0-9a-f]{64}$') {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid git source identity'
    }
    return
  }
  if ($Identity.kind -ceq 'content-sha256') {
    Assert-ExactProperties $Identity @('kind', 'content_sha256') 'source_identity'
    if ($Identity.content_sha256 -notmatch '^[0-9a-f]{64}$') {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid content source identity'
    }
    return
  }
  Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unknown source identity kind'
}

function Get-FoundationSourceIdentityKey {
  param($Identity)
  Assert-FoundationSourceIdentity $Identity
  if ($Identity.kind -ceq 'git') {
    return "git:$($Identity.commit):$($Identity.tree):$($Identity.content_sha256)"
  }
  return "content-sha256:$($Identity.content_sha256)"
}

function Assert-FoundationStringArray {
  param(
    [AllowEmptyCollection()][object[]]$Values,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$AllowEmpty,
    [string[]]$Allowed = @()
  )
  $Items = @($Values)
  if (-not $AllowEmpty -and $Items.Count -eq 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label must not be empty"
  }
  $Seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
  $Previous = $null
  foreach ($Value in $Items) {
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value) -or -not $Seen.Add([string]$Value)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label contains invalid or duplicate value"
    }
    if ($null -ne $Previous -and [StringComparer]::Ordinal.Compare($Previous, [string]$Value) -ge 0) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label is not ordinal-sorted"
    }
    if ($Allowed.Count -gt 0 -and $Allowed -cnotcontains [string]$Value) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label contains unsupported value"
    }
    $Previous = [string]$Value
  }
}

function Assert-FoundationTarget {
  param([Parameter(Mandatory = $true)][string]$Target)
  if (@('claude', 'codex', 'opencode') -cnotcontains $Target) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unsupported foundation target'
  }
}

function Assert-FoundationInstallRole {
  param([Parameter(Mandatory = $true)][string]$Role)
  if (@('consumer', 'hub') -cnotcontains $Role) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unsupported installation role'
  }
}

function Assert-FoundationSyncPolicy {
  param([Parameter(Mandatory = $true)]$Policy)
  Assert-ExactProperties $Policy @(
    'direction', 'default_role', 'consumer_push',
    'consumer_feedback_upload', 'consumer_session_upload',
    'credentials_included'
  ) 'sync_policy'
  if ($Policy.direction -cne 'hub-to-consumer' -or
      $Policy.default_role -cne 'consumer' -or
      $Policy.consumer_push -isnot [bool] -or [bool]$Policy.consumer_push -or
      $Policy.consumer_feedback_upload -isnot [bool] -or [bool]$Policy.consumer_feedback_upload -or
      $Policy.consumer_session_upload -isnot [bool] -or [bool]$Policy.consumer_session_upload -or
      $Policy.credentials_included -isnot [bool] -or [bool]$Policy.credentials_included) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Sync policy is not strictly hub-to-consumer'
  }
}

function Test-FoundationManagedDestinationForComponent {
  param($Component, [string]$Target)
  $Destination = [string]$Component.destination_relative_path
  $Type = [string]$Component.component_type
  switch ($Type) {
    'core' {
      return @{
        claude = @('claude/CLAUDE.md', 'claude/core/AGENTS.core.md')
        codex = @('codex/AGENTS.md')
        opencode = @('opencode/AGENTS.md')
      }[$Target] -ccontains $Destination
    }
    'agent' {
      return $Destination -ceq @{
        claude = "claude/agents/$($Component.component_id).md"
        codex = "codex/agents/$($Component.component_id).toml"
        opencode = "opencode/agents/$($Component.component_id).md"
      }[$Target]
    }
    'skill' {
      return $Destination -ceq @{
        claude = "claude/skills/$($Component.component_id)"
        codex = "agents/skills/$($Component.component_id)"
        opencode = "opencode/skills/$($Component.component_id)"
      }[$Target]
    }
    'config' {
      return $Target -ceq 'opencode' -and $Destination -ceq 'opencode/opencode.json'
    }
    'launcher' {
      return $Target -ceq 'opencode' -and $Destination -ceq 'local/bin/opencode-base.ps1'
    }
    'metadata' {
      return $Destination -in @(
        "$Target/.base/context-budget.json",
        "$Target/.base/target-manifest.json"
      )
    }
    default {
      return $false
    }
  }
}

function Get-FoundationRenderedContractRows {
  param([Parameter(Mandatory = $true)][string]$Target)
  Assert-FoundationTarget $Target
  $Contracts = @{
    claude = @(
      @('.claude/core/AGENTS.core.md', 'shared-core', 'core', 'claude/core/AGENTS.core.md'),
      @('.claude/CLAUDE.md', 'claude-rules', 'core', 'claude/CLAUDE.md'),
      @('.claude/agents/auditor.md', 'auditor', 'agent', 'claude/agents/auditor.md'),
      @('.claude/.base/context-budget.json', 'context-budget', 'metadata', 'claude/.base/context-budget.json'),
      @('.claude/.base/target-manifest.json', 'target-manifest', 'metadata', 'claude/.base/target-manifest.json')
    )
    codex = @(
      @('.codex/AGENTS.md', 'codex-rules', 'core', 'codex/AGENTS.md'),
      @('.codex/agents/auditor.toml', 'auditor', 'agent', 'codex/agents/auditor.toml'),
      @('.codex/.base/context-budget.json', 'context-budget', 'metadata', 'codex/.base/context-budget.json'),
      @('.codex/.base/target-manifest.json', 'target-manifest', 'metadata', 'codex/.base/target-manifest.json')
    )
    opencode = @(
      @('.config/opencode/AGENTS.md', 'opencode-rules', 'core', 'opencode/AGENTS.md'),
      @('.config/opencode/opencode.json', 'opencode-config', 'config', 'opencode/opencode.json'),
      @('.config/opencode/agents/auditor.md', 'auditor', 'agent', 'opencode/agents/auditor.md'),
      @('.config/opencode/.base/context-budget.json', 'context-budget', 'metadata', 'opencode/.base/context-budget.json'),
      @('.config/opencode/.base/target-manifest.json', 'target-manifest', 'metadata', 'opencode/.base/target-manifest.json'),
      @('.local/bin/opencode-base.ps1', 'opencode-launcher', 'launcher', 'local/bin/opencode-base.ps1')
    )
  }
  return @(
    foreach ($Values in @($Contracts[$Target])) {
      [pscustomobject][ordered]@{
        source_relative_path = [string]$Values[0]
        component_id = [string]$Values[1]
        component_type = [string]$Values[2]
        destination_relative_path = [string]$Values[3]
      }
    }
  )
}

function Assert-FoundationRenderedManifestContract {
  param([Parameter(Mandatory = $true)]$Manifest)
  $Expected = @(Get-FoundationRenderedContractRows ([string]$Manifest.target))
  $Active = @(
    $Manifest.components | Where-Object activation -CEQ 'ACTIVE_ELIGIBLE'
  )
  if ($Active.Count -ne $Expected.Count) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' `
      -Message 'Active component count differs from rendered target contract'
  }
  foreach ($Row in $Expected) {
    $Matches = @(
      $Active | Where-Object component_id -CEQ $Row.component_id
    )
    if ($Matches.Count -ne 1 -or
        $Matches[0].component_type -cne $Row.component_type -or
        $Matches[0].destination_relative_path -cne
          $Row.destination_relative_path) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' `
        -Message "Active component differs from rendered contract: $($Row.component_id)"
    }
  }
}

function Get-FoundationRowsDigest {
  param(
    [Parameter(Mandatory = $true)][object[]]$Rows,
    [Parameter(Mandatory = $true)][string]$PayloadRoot
  )
  if ($Rows.Count -eq 1 -and $Rows[0].path -ceq $PayloadRoot) {
    return [pscustomobject]@{ sha256 = $Rows[0].sha256; bytes = [int64]$Rows[0].bytes }
  }
  $Prefix = "$PayloadRoot/"
  $RelativeRows = @()
  foreach ($Row in $Rows) {
    if (-not ([string]$Row.path).StartsWith($Prefix, [StringComparison]::Ordinal)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Component file escaped payload root: $PayloadRoot"
    }
    $Relative = ([string]$Row.path).Substring($Prefix.Length)
    if (-not (Test-PortableRelativePath $Relative)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid relative component file path'
    }
    $RelativeRows += [pscustomobject]@{
      path = $Relative
      sha256 = $Row.sha256
      bytes = [int64]$Row.bytes
    }
  }
  $Paths = [string[]]@($RelativeRows | ForEach-Object path)
  [Array]::Sort($Paths, [StringComparer]::Ordinal)
  $Builder = [Text.StringBuilder]::new()
  [int64]$Total = 0
  foreach ($Path in $Paths) {
    $Row = $RelativeRows | Where-Object path -CEQ $Path | Select-Object -First 1
    $null = $Builder.Append($Path).Append([char]0).Append($Row.sha256).
      Append([char]0).Append([string]$Row.bytes).Append("`n")
    $Total += $Row.bytes
  }
  return [pscustomobject]@{
    sha256 = Get-FoundationSha256Hex ([Text.UTF8Encoding]::new($false).GetBytes($Builder.ToString()))
    bytes = $Total
  }
}

function Get-FoundationAggregateMap {
  param([object[]]$Components, [string]$Property)
  $Counts = @{}
  foreach ($Component in @($Components)) {
    $Key = [string]$Component.$Property
    if (-not $Counts.ContainsKey($Key)) { $Counts[$Key] = 0 }
    $Counts[$Key]++
  }
  return $Counts
}

function Assert-FoundationCountMap {
  param($Actual, [hashtable]$Expected, [string]$Label, [string[]]$AllowedKeys)
  if ($null -eq $Actual -or $Actual -isnot [Management.Automation.PSCustomObject]) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label must be an object"
  }
  $ActualNames = @($Actual.PSObject.Properties | ForEach-Object { $_.Name })
  if (@($ActualNames | Where-Object { $AllowedKeys -cnotcontains $_ }).Count -gt 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label contains unknown key"
  }
  if (@(Compare-Object @($Expected.Keys | Sort-Object) @($ActualNames | Sort-Object)).Count -ne 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label keys differ"
  }
  foreach ($Key in $Expected.Keys) {
    $Value = $Actual.PSObject.Properties[$Key].Value
    if ($Value -isnot [int] -and $Value -isnot [long]) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label count is not integer"
    }
    if ([int64]$Value -ne [int64]$Expected[$Key] -or [int64]$Value -lt 1) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label count differs"
    }
  }
}

function Assert-FoundationAggregateCounts {
  param($Counts, [object[]]$Components)
  Assert-ExactProperties $Counts @('total', 'by_type', 'by_verdict', 'by_activation') 'counts'
  if (($Counts.total -isnot [int] -and $Counts.total -isnot [long]) -or
      [int64]$Counts.total -ne @($Components).Count) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Manifest total count differs'
  }
  $Types = @('core', 'agent', 'skill', 'config', 'launcher', 'metadata', 'hook', 'mcp', 'plugin')
  $Verdicts = @('PASS', 'NOT_TESTED', 'BLOCKED', 'FAIL')
  $Activations = @(
    'ACTIVE_ELIGIBLE', 'QUARANTINE_NOT_TESTED', 'QUARANTINE_BLOCKED',
    'QUARANTINE_FAIL', 'QUARANTINE_DEPENDENCY',
    'QUARANTINE_UNSUPPORTED_ACTIVATION', 'QUARANTINE_INCOMPATIBLE_VERSION'
  )
  Assert-FoundationCountMap $Counts.by_type (Get-FoundationAggregateMap $Components 'component_type') 'counts.by_type' $Types
  Assert-FoundationCountMap $Counts.by_verdict (Get-FoundationAggregateMap $Components 'acceptance_verdict') 'counts.by_verdict' $Verdicts
  Assert-FoundationCountMap $Counts.by_activation (Get-FoundationAggregateMap $Components 'activation') 'counts.by_activation' $Activations
}

function Test-FoundationManifest {
  param([Parameter(Mandatory = $true)]$Manifest)
  $Top = @(
    'schema_version', 'release_id', 'channel', 'built_at_utc', 'vendor',
    'target', 'source_identity', 'installer_protocol_version', 'compatibility',
    'sync_policy',
    'files', 'components', 'counts', 'full_release_verdict'
  )
  Assert-ExactProperties $Manifest $Top 'manifest'
  if ($Manifest.schema_version -ne 2 -or $Manifest.vendor -cne 'llm-base' -or
      $Manifest.channel -cne 'foundation-canary' -or
      $Manifest.full_release_verdict -cne 'NOT_PASS' -or
      $Manifest.release_id -notmatch '^foundation-[a-z0-9][a-z0-9.-]{0,79}$' -or
      $Manifest.installer_protocol_version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Manifest constants differ'
  }
  Assert-FoundationTarget ([string]$Manifest.target)
  Assert-FoundationSyncPolicy $Manifest.sync_policy
  if ($Manifest.built_at_utc -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid UTC build timestamp'
  }
  $ParsedTimestamp = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse(
      [string]$Manifest.built_at_utc,
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::AssumeUniversal,
      [ref]$ParsedTimestamp)) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid build timestamp'
  }

  $SourceKey = Get-FoundationSourceIdentityKey $Manifest.source_identity
  Assert-ExactProperties $Manifest.compatibility @('windows', 'powershell', 'client_versions') 'compatibility'
  Assert-FoundationStringArray @($Manifest.compatibility.windows) 'compatibility.windows' -Allowed @('10', '11')
  Assert-FoundationStringArray @($Manifest.compatibility.powershell) 'compatibility.powershell' -Allowed @('5.1', '7')
  Assert-FoundationStringArray @($Manifest.compatibility.client_versions) 'compatibility.client_versions'
  foreach ($Version in @($Manifest.compatibility.client_versions)) {
    if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$') {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid target client version'
    }
  }

  $AllowedTypes = @(
    'core', 'agent', 'skill', 'config', 'launcher', 'metadata',
    'hook', 'mcp', 'plugin'
  )
  $AllowedVerdicts = @('PASS', 'NOT_TESTED', 'BLOCKED', 'FAIL')
  $AllowedActivations = @(
    'ACTIVE_ELIGIBLE', 'QUARANTINE_NOT_TESTED', 'QUARANTINE_BLOCKED',
    'QUARANTINE_FAIL', 'QUARANTINE_DEPENDENCY',
    'QUARANTINE_UNSUPPORTED_ACTIVATION', 'QUARANTINE_INCOMPATIBLE_VERSION'
  )
  $Ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $ExactIds = @{}
  $Destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $PreviousId = $null
  foreach ($Component in @($Manifest.components)) {
    Assert-ExactProperties $Component @(
      'component_id', 'component_type', 'source_identity', 'payload_relative_path',
      'destination_relative_path', 'sha256', 'bytes', 'dependencies',
      'acceptance_verdict', 'evidence_ids', 'activation', 'quarantine_reason'
    ) 'component'
    if ($Component.component_id -notmatch '^[a-z0-9][a-z0-9._-]{0,99}$' -or
        -not $Ids.Add([string]$Component.component_id) -or
        ($null -ne $PreviousId -and [StringComparer]::Ordinal.Compare($PreviousId, [string]$Component.component_id) -ge 0)) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid, duplicate or unsorted component ID'
    }
    $PreviousId = [string]$Component.component_id
    $ExactIds[[string]$Component.component_id] = $Component
    if ($AllowedTypes -cnotcontains [string]$Component.component_type -or
        $AllowedVerdicts -cnotcontains [string]$Component.acceptance_verdict -or
        $AllowedActivations -cnotcontains [string]$Component.activation -or
        $Component.sha256 -notmatch '^[0-9a-f]{64}$' -or
        ($Component.bytes -isnot [int] -and $Component.bytes -isnot [long]) -or
        [int64]$Component.bytes -lt 0 -or
        -not (Test-PortableRelativePath ([string]$Component.payload_relative_path)) -or
        (Get-FoundationSourceIdentityKey $Component.source_identity) -cne $SourceKey) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid component row'
    }
    Assert-FoundationStringArray @($Component.dependencies) 'component.dependencies' -AllowEmpty
    Assert-FoundationStringArray @($Component.evidence_ids) 'component.evidence_ids' -AllowEmpty

    if ($Component.activation -ceq 'ACTIVE_ELIGIBLE') {
      if ($Component.acceptance_verdict -cne 'PASS' -or @($Component.evidence_ids).Count -eq 0 -or
          $null -ne $Component.quarantine_reason -or
          -not (Test-FoundationManagedDestinationForComponent $Component $Manifest.target) -or
          -not $Destinations.Add([string]$Component.destination_relative_path)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid active component'
      }
    } else {
      if ($null -ne $Component.destination_relative_path -or
          [string]::IsNullOrWhiteSpace([string]$Component.quarantine_reason)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid quarantine component'
      }
      $ExpectedReason = @{
        QUARANTINE_NOT_TESTED = 'NOT_TESTED'
        QUARANTINE_BLOCKED = 'BLOCKED'
        QUARANTINE_FAIL = 'FAIL'
        QUARANTINE_DEPENDENCY = 'DEPENDENCY'
        QUARANTINE_UNSUPPORTED_ACTIVATION = 'UNSUPPORTED_ACTIVATION'
        QUARANTINE_INCOMPATIBLE_VERSION = 'INCOMPATIBLE_VERSION'
      }[[string]$Component.activation]
      if ($Component.quarantine_reason -cne $ExpectedReason) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Quarantine reason differs'
      }
      if ($Component.acceptance_verdict -ceq 'FAIL' -and $Component.activation -cne 'QUARANTINE_FAIL') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'FAIL activation differs'
      }
      if ($Component.acceptance_verdict -ceq 'BLOCKED' -and $Component.activation -cne 'QUARANTINE_BLOCKED') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'BLOCKED activation differs'
      }
      if ($Component.acceptance_verdict -ceq 'NOT_TESTED' -and $Component.activation -cne 'QUARANTINE_NOT_TESTED') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'NOT_TESTED activation differs'
      }
      if ($Component.acceptance_verdict -ceq 'PASS' -and
          @('hook', 'mcp', 'plugin') -contains [string]$Component.component_type -and
          $Component.activation -cne 'QUARANTINE_UNSUPPORTED_ACTIVATION') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unsupported active type not quarantined'
      }
    }
  }

  foreach ($Component in @($Manifest.components)) {
    foreach ($Dependency in @($Component.dependencies)) {
      if ($Dependency -ceq $Component.component_id -or -not $ExactIds.ContainsKey([string]$Dependency)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid component dependency'
      }
    }
  }

  $FilePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $PreviousPath = $null
  $ComponentFileMap = @{}
  foreach ($File in @($Manifest.files)) {
    Assert-ExactProperties $File @('path', 'role', 'component_id', 'sha256', 'bytes') 'file'
    if (-not (Test-PortableRelativePath ([string]$File.path)) -or
        -not $FilePaths.Add([string]$File.path) -or
        ($null -ne $PreviousPath -and [StringComparer]::Ordinal.Compare($PreviousPath, [string]$File.path) -ge 0) -or
        @('installer', 'schema', 'doc', 'component') -cnotcontains [string]$File.role -or
        $File.sha256 -notmatch '^[0-9a-f]{64}$' -or
        ($File.bytes -isnot [int] -and $File.bytes -isnot [long]) -or [int64]$File.bytes -lt 0) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid, duplicate or unsorted file row'
    }
    $PreviousPath = [string]$File.path
    if ($File.role -ceq 'component') {
      if ([string]::IsNullOrWhiteSpace([string]$File.component_id) -or
          -not $ExactIds.ContainsKey([string]$File.component_id)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Component file reference is invalid'
      }
      if (-not $ComponentFileMap.ContainsKey([string]$File.component_id)) {
        $ComponentFileMap[[string]$File.component_id] = @()
      }
      $ComponentFileMap[[string]$File.component_id] += $File
    } elseif ($null -ne $File.component_id) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Non-component file has component ID'
    }
  }

  foreach ($Component in @($Manifest.components)) {
    $Rows = @($ComponentFileMap[[string]$Component.component_id])
    if ($Rows.Count -eq 0) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Component has no file rows'
    }
    $Digest = Get-FoundationRowsDigest $Rows ([string]$Component.payload_relative_path)
    if ($Digest.sha256 -cne $Component.sha256 -or $Digest.bytes -ne [int64]$Component.bytes) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Component digest differs from files'
    }
  }
  Assert-FoundationAggregateCounts $Manifest.counts @($Manifest.components)
}
