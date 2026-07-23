function Get-FoundationSha256Hex {
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)
  $Algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return -join ($Algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $Algorithm.Dispose()
  }
}

function Sort-FoundationObjectsOrdinal {
  param(
    [AllowEmptyCollection()][object[]]$Items,
    [Parameter(Mandatory = $true)][string]$Property
  )
  $Values = [string[]]@($Items | ForEach-Object { [string]$_.$Property })
  [Array]::Sort($Values, [StringComparer]::Ordinal)
  return @(
    foreach ($Value in $Values) {
      $Items | Where-Object { [string]$_.$Property -ceq $Value } | Select-Object -First 1
    }
  )
}

function Get-Sha256Lower {
  param([Parameter(Mandatory = $true)][string]$Path)
  $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Throw-FoundationError -Code 'UNSAFE_PATH' -Message "Expected a regular file: $Path"
  }
  $Stream = [IO.File]::Open($Item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  $Algorithm = [Security.Cryptography.SHA256]::Create()
  try {
    return -join ($Algorithm.ComputeHash($Stream) | ForEach-Object { $_.ToString('x2') })
  } finally {
    $Algorithm.Dispose()
    $Stream.Dispose()
  }
}

function Assert-ExactProperties {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if ($null -eq $Object -or $Object -isnot [Management.Automation.PSCustomObject]) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label must be an object"
  }
  $Actual = @($Object.PSObject.Properties.Name | Sort-Object)
  $Wanted = @($Expected | Sort-Object)
  if (@(Compare-Object -ReferenceObject $Wanted -DifferenceObject $Actual).Count -ne 0) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "$Label has an unknown or missing property"
  }
}

function Skip-FoundationJsonWhitespace {
  while ($script:FoundationJsonIndex -lt $script:FoundationJsonText.Length -and
      " `t`r`n".IndexOf($script:FoundationJsonText[$script:FoundationJsonIndex]) -ge 0) {
    $script:FoundationJsonIndex++
  }
}

function Read-FoundationJsonString {
  if ($script:FoundationJsonIndex -ge $script:FoundationJsonText.Length -or
      $script:FoundationJsonText[$script:FoundationJsonIndex] -ne '"') {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Expected JSON string'
  }
  $Start = $script:FoundationJsonIndex
  $script:FoundationJsonIndex++
  $Escaped = $false
  while ($script:FoundationJsonIndex -lt $script:FoundationJsonText.Length) {
    $Character = $script:FoundationJsonText[$script:FoundationJsonIndex]
    if ([int][char]$Character -lt 0x20) {
      Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Control character in JSON string'
    }
    if ($Escaped) {
      if ('"\/bfnrtu'.IndexOf($Character) -lt 0) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid JSON escape'
      }
      if ($Character -eq 'u') {
        if ($script:FoundationJsonIndex + 4 -ge $script:FoundationJsonText.Length) {
          Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Truncated JSON unicode escape'
        }
        $Hex = $script:FoundationJsonText.Substring($script:FoundationJsonIndex + 1, 4)
        if ($Hex -notmatch '^[0-9a-fA-F]{4}$') {
          Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid JSON unicode escape'
        }
        $script:FoundationJsonIndex += 4
      }
      $Escaped = $false
    } elseif ($Character -eq '\') {
      $Escaped = $true
    } elseif ($Character -eq '"') {
      $script:FoundationJsonIndex++
      $Raw = $script:FoundationJsonText.Substring($Start, $script:FoundationJsonIndex - $Start)
      try { return (ConvertFrom-Json -InputObject $Raw -ErrorAction Stop) }
      catch { Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid JSON string token' }
    }
    $script:FoundationJsonIndex++
  }
  Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unterminated JSON string'
}

function Read-FoundationJsonValue {
  param([int]$Depth = 0)
  if ($Depth -gt 64) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'JSON nesting exceeds 64'
  }
  Skip-FoundationJsonWhitespace
  if ($script:FoundationJsonIndex -ge $script:FoundationJsonText.Length) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unexpected end of JSON'
  }
  $Character = $script:FoundationJsonText[$script:FoundationJsonIndex]
  if ($Character -eq '{') {
    $script:FoundationJsonIndex++
    $Names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    Skip-FoundationJsonWhitespace
    if ($script:FoundationJsonIndex -lt $script:FoundationJsonText.Length -and
        $script:FoundationJsonText[$script:FoundationJsonIndex] -eq '}') {
      $script:FoundationJsonIndex++
      return
    }
    while ($true) {
      Skip-FoundationJsonWhitespace
      $Name = [string](Read-FoundationJsonString)
      if (-not $Names.Add($Name)) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Duplicate JSON property: $Name"
      }
      Skip-FoundationJsonWhitespace
      if ($script:FoundationJsonIndex -ge $script:FoundationJsonText.Length -or
          $script:FoundationJsonText[$script:FoundationJsonIndex] -ne ':') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Expected JSON colon'
      }
      $script:FoundationJsonIndex++
      Read-FoundationJsonValue ($Depth + 1)
      Skip-FoundationJsonWhitespace
      if ($script:FoundationJsonIndex -ge $script:FoundationJsonText.Length) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unterminated JSON object'
      }
      $Separator = $script:FoundationJsonText[$script:FoundationJsonIndex]
      $script:FoundationJsonIndex++
      if ($Separator -eq '}') { return }
      if ($Separator -ne ',') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Expected JSON object separator'
      }
    }
  }
  if ($Character -eq '[') {
    $script:FoundationJsonIndex++
    Skip-FoundationJsonWhitespace
    if ($script:FoundationJsonIndex -lt $script:FoundationJsonText.Length -and
        $script:FoundationJsonText[$script:FoundationJsonIndex] -eq ']') {
      $script:FoundationJsonIndex++
      return
    }
    while ($true) {
      Read-FoundationJsonValue ($Depth + 1)
      Skip-FoundationJsonWhitespace
      if ($script:FoundationJsonIndex -ge $script:FoundationJsonText.Length) {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Unterminated JSON array'
      }
      $Separator = $script:FoundationJsonText[$script:FoundationJsonIndex]
      $script:FoundationJsonIndex++
      if ($Separator -eq ']') { return }
      if ($Separator -ne ',') {
        Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Expected JSON array separator'
      }
    }
  }
  if ($Character -eq '"') {
    $null = Read-FoundationJsonString
    return
  }
  $Remaining = $script:FoundationJsonText.Substring($script:FoundationJsonIndex)
  if ($Remaining -match '^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?') {
    $script:FoundationJsonIndex += $Matches[0].Length
    return
  }
  foreach ($Literal in @('true', 'false', 'null')) {
    if ($Remaining.StartsWith($Literal, [StringComparison]::Ordinal)) {
      $script:FoundationJsonIndex += $Literal.Length
      return
    }
  }
  Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Invalid JSON value'
}

function Assert-FoundationJsonLexicallyStrict {
  param([Parameter(Mandatory = $true)][string]$Text)
  $script:FoundationJsonText = $Text
  $script:FoundationJsonIndex = 0
  Read-FoundationJsonValue 0
  Skip-FoundationJsonWhitespace
  if ($script:FoundationJsonIndex -ne $script:FoundationJsonText.Length) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'Trailing JSON data'
  }
}

function Read-JsonFileStrict {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxBytes = 1048576
  )
  $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
      $Item.Length -le 0 -or $Item.Length -gt $MaxBytes) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "JSON file outside bounds: $Path"
  }
  $Bytes = [IO.File]::ReadAllBytes($Item.FullName)
  $Utf8 = [Text.UTF8Encoding]::new($false, $true)
  try { $Text = $Utf8.GetString($Bytes) }
  catch { Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "JSON is not strict UTF-8: $Path" }
  Assert-FoundationJsonLexicallyStrict $Text
  try {
    $ConvertCommand = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($ConvertCommand.Parameters.ContainsKey('DateKind')) {
      return ConvertFrom-Json -InputObject $Text -DateKind String -ErrorAction Stop
    }
    return ConvertFrom-Json -InputObject $Text -ErrorAction Stop
  }
  catch { Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "JSON parse failed: $Path" }
}
