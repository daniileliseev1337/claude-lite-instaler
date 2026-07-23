It 'reads bounded strict UTF-8 JSON' {
  $Root = New-TestRoot 'json-valid'
  try {
    $Path = Join-Path $Root 'valid.json'
    [IO.File]::WriteAllText($Path, '{"a":1}', [Text.UTF8Encoding]::new($false))
    $Value = Read-JsonFileStrict $Path 1024
    Assert-Equal 1 $Value.a
  } finally { Remove-TestRoot $Root }
}

It 'rejects unknown properties' {
  $Object = [pscustomobject]@{ a = 1; b = 2 }
  Assert-ThrowsCode 'INVALID_PACKAGE' {
    Assert-ExactProperties $Object @('a') 'fixture'
  }
}

It 'returns lowercase SHA-256' {
  $Root = New-TestRoot 'sha'
  try {
    $Path = Join-Path $Root 'bytes.bin'
    [IO.File]::WriteAllBytes($Path, [byte[]](0, 1, 2))
    Assert-Equal 'ae4b3280e56e2faf83f414a6e3dabe9d5fbe18976544c05fed121accb85b53fc' (Get-Sha256Lower $Path)
  } finally { Remove-TestRoot $Root }
}

foreach ($Case in @(
  @{ name = 'duplicate top-level key'; json = '{"a":1,"a":2}' },
  @{ name = 'duplicate nested key'; json = '{"x":{"a":1,"a":2}}' },
  @{ name = 'escaped-equivalent duplicate key'; json = '{"a":1,"\u0061":2}' },
  @{ name = 'trailing JSON value'; json = '{"a":1}{"b":2}' }
)) {
  It "rejects $($Case.name)" {
    $Root = New-TestRoot 'json-invalid'
    try {
      $Path = Join-Path $Root 'invalid.json'
      [IO.File]::WriteAllText($Path, $Case.json, [Text.UTF8Encoding]::new($false))
      Assert-ThrowsCode 'INVALID_PACKAGE' { Read-JsonFileStrict $Path 1024 }
    } finally { Remove-TestRoot $Root }
  }
}

It 'rejects an invalid UTF-8 sequence' {
  $Root = New-TestRoot 'json-utf8'
  try {
    $Path = Join-Path $Root 'invalid.json'
    [IO.File]::WriteAllBytes($Path, [byte[]](0x7B, 0x22, 0x61, 0x22, 0x3A, 0xC3, 0x28, 0x7D))
    Assert-ThrowsCode 'INVALID_PACKAGE' { Read-JsonFileStrict $Path 1024 }
  } finally { Remove-TestRoot $Root }
}

It 'rejects JSON beyond the byte limit' {
  $Root = New-TestRoot 'json-limit'
  try {
    $Path = Join-Path $Root 'large.json'
    [IO.File]::WriteAllText($Path, '{"message":"too long"}', [Text.UTF8Encoding]::new($false))
    Assert-ThrowsCode 'INVALID_PACKAGE' { Read-JsonFileStrict $Path 8 }
  } finally { Remove-TestRoot $Root }
}

