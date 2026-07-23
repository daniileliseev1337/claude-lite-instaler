It 'ships one offline mobile-ready employee dashboard' {
  $Path = Join-Path $PSScriptRoot '..\docs\codex-foundation-dashboard.html'
  Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) 'Dashboard HTML is missing'
  $Html = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
  Assert-True $Html.Contains('name="viewport"')
  Assert-True $Html.Contains('.\install.ps1 plan')
  Assert-True $Html.Contains('.\install.ps1 install')
  Assert-True $Html.Contains('.\install.ps1 doctor')
  Assert-True $Html.Contains('.\install.ps1 inventory')
  Assert-True $Html.Contains('.\install.ps1 rollback')
  Assert-True $Html.Contains('FULL RELEASE: NOT PASS')
  Assert-True $Html.Contains('FOUNDATION SYNTHETIC: PASS')
  Assert-True $Html.Contains('BLOCKED_APPROVED_FOUNDATION_SOURCE')
  Assert-False ($Html -match '(?i)https?://')
  Assert-False ($Html -match '(?i)<script[^>]+src=')
  Assert-False ($Html -match 'TODO|TBD|FIXME|\{\{')
}

It 'dashboard exposes accessible copy controls and reduced-motion support' {
  $Path = Join-Path $PSScriptRoot '..\docs\codex-foundation-dashboard.html'
  $Html = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path))
  Assert-True ($Html -match 'aria-label="[^"]+"')
  Assert-True $Html.Contains('@media (prefers-reduced-motion: reduce)')
  Assert-True $Html.Contains(':focus-visible')
}

It 'publishes the synthetic pass without overstating full release' {
  $ReadmePath = Join-Path $PSScriptRoot '..\README.md'
  $Readme = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $ReadmePath))
  Assert-True $Readme.Contains('FOUNDATION_SYNTHETIC_PASS')
  Assert-True $Readme.Contains('FULL_RELEASE_NOT_PASS')
  Assert-True $Readme.Contains('BLOCKED_APPROVED_FOUNDATION_SOURCE')
  Assert-False $Readme.Contains('FULL_RELEASE_PASS')
}
