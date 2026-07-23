[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$SourceRoot,
  [Parameter(Mandatory = $true)][string]$InventoryPath,
  [Parameter(Mandatory = $true)][string]$OutputRoot
)

$ErrorActionPreference = 'Stop'
$SourceFiles = @(
  'Foundation.Errors.ps1',
  'Foundation.Json.ps1',
  'Foundation.Paths.ps1',
  'Foundation.Manifest.ps1',
  'Foundation.Classifier.ps1',
  'Foundation.Package.ps1'
)
foreach ($SourceFile in $SourceFiles) {
  . (Join-Path $PSScriptRoot "..\src\foundation\$SourceFile")
}

$Result = New-FoundationPackage $SourceRoot $InventoryPath $OutputRoot
Write-Output (ConvertTo-Json $Result -Depth 10)

