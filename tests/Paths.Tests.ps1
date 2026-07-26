$RejectedPortablePaths = @(
  '', '.', '..', '../x', 'x/../y', '/absolute', '\absolute',
  'C:/absolute', '//server/share', 'x//y', 'x\y', 'x/.hidden/../y',
  'x.', 'x ', 'CON', 'aux/file', 'x*/y', "x$([char]0)y"
)

foreach ($Value in $RejectedPortablePaths) {
  It "rejects portable path <$Value>" {
    Assert-False (Test-PortableRelativePath $Value)
  }
}

It 'accepts a portable nested path' {
  Assert-True (Test-PortableRelativePath 'agents/skills/example/SKILL.md')
}

It 'maps native managed namespaces for Claude Codex and OpenCode' {
  $Root = New-TestRoot 'managed-path'
  try {
    $FakeUserProfile = Join-Path $Root 'home'
    [IO.Directory]::CreateDirectory($FakeUserProfile) | Out-Null
    $Agent = Resolve-ManagedDestination 'codex/agents/a.toml' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.codex\agents\a.toml'))) $Agent
    $Skill = Resolve-ManagedDestination 'agents/skills/example-skill' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.agents\skills\example-skill'))) $Skill
    $Core = Resolve-ManagedDestination 'codex/AGENTS.md' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.codex\AGENTS.md'))) $Core
    $Claude = Resolve-ManagedDestination 'claude/CLAUDE.md' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.claude\CLAUDE.md'))) $Claude
    $ClaudeCore = Resolve-ManagedDestination 'claude/core/AGENTS.core.md' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.claude\core\AGENTS.core.md'))) $ClaudeCore
    $OpenCode = Resolve-ManagedDestination 'opencode/opencode.json' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.config\opencode\opencode.json'))) $OpenCode
    $Launcher = Resolve-ManagedDestination 'local/bin/opencode-base.ps1' $FakeUserProfile
    Assert-Equal ([IO.Path]::GetFullPath((Join-Path $FakeUserProfile '.local\bin\opencode-base.ps1'))) $Launcher
  } finally { Remove-TestRoot $Root }
}

It 'rejects unmanaged config path' {
  $Root = New-TestRoot 'unmanaged'
  try {
    Assert-ThrowsCode 'UNSAFE_PATH' {
      Resolve-ManagedDestination 'codex/config.toml' $Root
    }
  } finally { Remove-TestRoot $Root }
}

It 'rejects OpenCode credentials and auth-store paths' {
  $Root = New-TestRoot 'auth-path'
  try {
    foreach ($Path in @(
        'opencode/auth.json',
        'local/share/opencode/auth.json',
        'opencode/.env'
      )) {
      Assert-ThrowsCode 'UNSAFE_PATH' {
        Resolve-ManagedDestination $Path $Root
      }
    }
  } finally { Remove-TestRoot $Root }
}

It 'computes deterministic directory tree digest and file rows' {
  $Root = New-TestRoot 'tree-digest'
  try {
    $Tree = Join-Path $Root 'skill'
    [IO.Directory]::CreateDirectory((Join-Path $Tree 'scripts')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $Tree 'SKILL.md'), "hello`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes((Join-Path $Tree 'scripts\a.bin'), [byte[]](3, 2, 1))
    $A = Get-FoundationPayloadDigest $Tree
    $B = Get-FoundationPayloadDigest $Tree
    Assert-Equal $A.sha256 $B.sha256
    Assert-Equal 9 $A.bytes
    Assert-Equal @('SKILL.md', 'scripts/a.bin') @($A.files.path)
    Assert-Equal 2 @($A.files).Count
  } finally { Remove-TestRoot $Root }
}

It 'rejects a reparse directory while hashing payload' {
  $Root = New-TestRoot 'tree-reparse'
  try {
    $Tree = Join-Path $Root 'skill'
    $Outside = Join-Path $Root 'outside'
    [IO.Directory]::CreateDirectory($Tree) | Out-Null
    [IO.Directory]::CreateDirectory($Outside) | Out-Null
    [IO.File]::WriteAllText((Join-Path $Outside 'secret.txt'), 'secret')
    $Link = Join-Path $Tree 'linked'
    New-Item -ItemType Junction -Path $Link -Target $Outside | Out-Null
    Assert-ThrowsCode 'UNSAFE_PATH' { Get-FoundationPayloadDigest $Tree }
  } finally { Remove-TestRoot $Root }
}
