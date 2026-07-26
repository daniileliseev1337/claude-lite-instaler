[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$OutputPath)

$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$SourceRoot = Join-Path $RepoRoot 'src\foundation'
$Order = @(
  'Foundation.Errors.ps1',
  'Foundation.Json.ps1',
  'Foundation.Paths.ps1',
  'Foundation.Manifest.ps1',
  'Foundation.Classifier.ps1',
  'Foundation.Package.ps1',
  'Foundation.Planner.ps1',
  'Foundation.State.ps1',
  'Foundation.Transaction.ps1',
  'Foundation.Doctor.ps1',
  'Foundation.Rollback.ps1',
  'Foundation.Cli.ps1',
  'Install.Entry.ps1'
)

$FunctionNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$Builder = [Text.StringBuilder]::new()
$null = $Builder.AppendLine('# generated-by: tools/bundle-installer.ps1')
$null = $Builder.AppendLine('# LLM Base Foundation Installer · offline/current-user')
$null = $Builder.AppendLine('$ErrorActionPreference = ''Stop''')
$null = $Builder.AppendLine()
foreach ($Name in $Order) {
  $Path = Join-Path $SourceRoot $Name
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing bundle source: $Name"
  }
  $Tokens = $null
  $Errors = $null
  $Ast = [Management.Automation.Language.Parser]::ParseFile(
    $Path,
    [ref]$Tokens,
    [ref]$Errors
  )
  if (@($Errors).Count -gt 0) { throw "Parse error in $Name" }
  foreach ($Function in @($Ast.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.FunctionDefinitionAst]
      }, $true))) {
    if (-not $FunctionNames.Add($Function.Name)) {
      throw "Duplicate bundled function: $($Function.Name)"
    }
  }
  $Text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true)).
    Replace("`r`n", "`n").TrimEnd("`n")
  $null = $Builder.AppendLine("# source: $Name")
  $null = $Builder.AppendLine($Text)
  $null = $Builder.AppendLine()
}
$null = $Builder.AppendLine('[Environment]::Exit((Invoke-FoundationEntry -CliArgs $args))')
$Text = $Builder.ToString().Replace("`r`n", "`n")
$Bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
$AbsoluteOutput = [IO.Path]::GetFullPath($OutputPath)
$Parent = Split-Path -Parent $AbsoluteOutput
if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
  throw "Output parent does not exist: $Parent"
}
$Stream = [IO.File]::Open(
  $AbsoluteOutput,
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
$Tokens = $null
$Errors = $null
$Ast = [Management.Automation.Language.Parser]::ParseFile(
  $AbsoluteOutput,
  [ref]$Tokens,
  [ref]$Errors
)
if (@($Errors).Count -gt 0) { throw 'Generated installer parse failed' }
$Forbidden = @(
  'Invoke-WebRequest','Invoke-RestMethod','Start-BitsTransfer',
  'Start-Process','git','curl','wget','claude','codex','opencode'
)
$Commands = @(
  $Ast.FindAll({
    param($Node)
    $Node -is [Management.Automation.Language.CommandAst]
  }, $true) | ForEach-Object { $_.GetCommandName() }
)
foreach ($Name in $Forbidden) {
  if ($Commands -contains $Name) { throw "Forbidden runtime command: $Name" }
}
Write-Output ([pscustomobject]@{
  output_path = $AbsoluteOutput
  sha256 = (Get-FileHash -LiteralPath $AbsoluteOutput -Algorithm SHA256).Hash.ToLowerInvariant()
  bytes = $Bytes.Length
})
