[CmdletBinding()]
param([string[]]$Files = @())

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')

$SourceRoot = Join-Path $PSScriptRoot '..\src\foundation'
if (Test-Path -LiteralPath $SourceRoot) {
  Get-ChildItem -LiteralPath $SourceRoot -Filter '*.ps1' -File |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
}

$SupportPath = Join-Path $PSScriptRoot 'TestSupport.ps1'
if (Test-Path -LiteralPath $SupportPath) {
  . $SupportPath
}

$Selected = if ($Files.Count) {
  $Files | ForEach-Object { Get-Item -LiteralPath $_ }
} else {
  Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.Tests.ps1' -File |
    Sort-Object Name
}

$Selected | ForEach-Object { . $_.FullName }
Write-Output "RESULT passed=$script:Passed failed=$script:Failed"
if ($script:Failed) { exit 1 }
