function Test-PortableRelativePath {
  param([AllowEmptyString()][string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 240 -or
      $Value.Contains('\') -or $Value.StartsWith('/') -or $Value.Contains(':') -or
      $Value.Contains('//') -or $Value.IndexOfAny([char[]]'<>"|?*') -ge 0 -or
      $Value.Normalize([Text.NormalizationForm]::FormC) -cne $Value -or
      @($Value.ToCharArray() | Where-Object { [char]::IsControl($_) }).Count -gt 0) {
    return $false
  }
  $Parts = @($Value.Split('/'))
  $Reserved = '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
  if ($Parts.Count -eq 0 -or $Parts.Count -gt 32) { return $false }
  foreach ($Part in $Parts) {
    if ($Part -in @('', '.', '..') -or $Part.Length -gt 100 -or
        $Part.EndsWith('.') -or $Part.EndsWith(' ') -or $Part -match $Reserved) {
      return $false
    }
  }
  return $true
}

function Resolve-ManagedDestination {
  param(
    [Parameter(Mandatory = $true)][string]$DestinationRelativePath,
    [Parameter(Mandatory = $true)][string]$UserProfile
  )
  if (-not (Test-PortableRelativePath $DestinationRelativePath)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Destination is not a portable relative path'
  }
  $Parts = @($DestinationRelativePath.Split('/'))
  $Allowed = (
    $DestinationRelativePath -ceq 'codex/AGENTS.md' -or
    ($Parts.Count -eq 3 -and $Parts[0] -ceq 'codex' -and
      $Parts[1] -ceq 'agents' -and $Parts[2].EndsWith('.toml', [StringComparison]::Ordinal)) -or
    ($Parts.Count -ge 3 -and $Parts[0] -ceq 'agents' -and $Parts[1] -ceq 'skills')
  )
  if (-not $Allowed) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Destination is outside the foundation allowlist'
  }
  $Relative = if ($Parts[0] -ceq 'codex') {
    '.codex\' + (($Parts | Select-Object -Skip 1) -join '\')
  } else {
    '.agents\' + (($Parts | Select-Object -Skip 1) -join '\')
  }
  $ProfileRoot = [IO.Path]::GetFullPath($UserProfile)
  $Result = [IO.Path]::GetFullPath((Join-Path $ProfileRoot $Relative))
  if (-not $Result.StartsWith(
      $ProfileRoot + [IO.Path]::DirectorySeparatorChar,
      [StringComparison]::OrdinalIgnoreCase)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message 'Destination escaped user profile'
  }
  return $Result
}

function Assert-SafeExistingDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)
  $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if (-not $Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Unsafe directory: $Path"
  }
  $Lexical = [IO.Path]::GetFullPath($Path)
  $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
  if (-not $Lexical.Equals($Resolved, [StringComparison]::OrdinalIgnoreCase)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Directory identity changed: $Path"
  }
}

function Get-FoundationPayloadDigest {
  param([Parameter(Mandatory = $true)][string]$Path)
  $RootItem = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($RootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Payload is a reparse point: $Path"
  }
  if (-not $RootItem.PSIsContainer) {
    $Hash = Get-Sha256Lower $RootItem.FullName
    return [pscustomobject]@{
      sha256 = $Hash
      bytes = [int64]$RootItem.Length
      files = @([pscustomobject]@{ path = ''; sha256 = $Hash; bytes = [int64]$RootItem.Length })
    }
  }

  $Root = [IO.Path]::GetFullPath($RootItem.FullName)
  $Pending = [Collections.Generic.Queue[string]]::new()
  $Pending.Enqueue($Root)
  $Rows = New-Object Collections.Generic.List[object]
  $CasePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  while ($Pending.Count -gt 0) {
    $Directory = $Pending.Dequeue()
    Assert-SafeExistingDirectory $Directory
    foreach ($Child in @(Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop)) {
      if ($Child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Payload contains reparse point: $($Child.FullName)"
      }
      if ($Child.PSIsContainer) {
        $Pending.Enqueue($Child.FullName)
        continue
      }
      $Relative = $Child.FullName.Substring($Root.Length).TrimStart('\').Replace('\', '/')
      if (-not (Test-PortableRelativePath $Relative) -or -not $CasePaths.Add($Relative)) {
        Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Unsafe or colliding payload path: $Relative"
      }
      $Rows.Add([pscustomobject]@{
        path = $Relative
        sha256 = Get-Sha256Lower $Child.FullName
        bytes = [int64]$Child.Length
      })
    }
  }
  if ($Rows.Count -eq 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Payload directory is empty'
  }
  $Paths = [string[]]@($Rows | ForEach-Object { $_.path })
  [Array]::Sort($Paths, [StringComparer]::Ordinal)
  $Sorted = @(
    foreach ($SortedPath in $Paths) {
      $Rows | Where-Object { $_.path -ceq $SortedPath } | Select-Object -First 1
    }
  )
  $Builder = [Text.StringBuilder]::new()
  [int64]$TotalBytes = 0
  foreach ($Row in $Sorted) {
    $null = $Builder.Append($Row.path).Append([char]0).Append($Row.sha256).
      Append([char]0).Append([string]$Row.bytes).Append("`n")
    $TotalBytes += $Row.bytes
  }
  $CanonicalBytes = [Text.UTF8Encoding]::new($false).GetBytes($Builder.ToString())
  return [pscustomobject]@{
    sha256 = Get-FoundationSha256Hex $CanonicalBytes
    bytes = $TotalBytes
    files = $Sorted
  }
}
