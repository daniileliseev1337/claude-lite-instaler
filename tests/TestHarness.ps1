$script:Passed = 0
$script:Failed = 0
$script:CurrentTestRoot = $null

function It {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Body
  )
  try {
    & $Body
    $script:Passed++
    Write-Output "PASS $Name"
  } catch {
    $script:Failed++
    Write-Output "FAIL $Name :: $($_.Exception.Message)"
  }
}

function Assert-Equal {
  param($Expected, $Actual, [string]$Message = '')
  if ($Expected -is [array] -or $Actual -is [array]) {
    $ExpectedJson = ConvertTo-Json @($Expected) -Compress -Depth 20
    $ActualJson = ConvertTo-Json @($Actual) -Compress -Depth 20
    if ($ExpectedJson -cne $ActualJson) {
      throw "Expected <$ExpectedJson>, got <$ActualJson>. $Message"
    }
    return
  }
  if ($Expected -cne $Actual) {
    throw "Expected <$Expected>, got <$Actual>. $Message"
  }
}

function Assert-True {
  param([bool]$Value, [string]$Message = 'Expected true')
  if (-not $Value) { throw $Message }
}

function Assert-False {
  param([bool]$Value, [string]$Message = 'Expected false')
  if ($Value) { throw $Message }
}

function Assert-ThrowsCode {
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][scriptblock]$Body
  )
  $Caught = $null
  try { & $Body } catch { $Caught = $_.Exception }
  if ($null -eq $Caught) { throw "Expected coded exception $Code" }
  if ([string]$Caught.Data['FoundationCode'] -cne $Code) {
    throw "Expected coded exception $Code, got $($Caught.Data['FoundationCode'])"
  }
}

function New-TestRoot {
  param([string]$Name = 'case')
  $Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
  $Base = Join-Path $Repo '.work\tests'
  [IO.Directory]::CreateDirectory($Base) | Out-Null
  $Id = [Guid]::NewGuid().ToString('N')
  $Path = Join-Path $Base "$Name-$Id"
  [IO.Directory]::CreateDirectory($Path) | Out-Null
  $script:CurrentTestRoot = $Path
  return $Path
}

function Remove-TestRoot {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return
  }
  $Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
  $Allowed = [IO.Path]::GetFullPath((Join-Path $Repo '.work\tests'))
  $Resolved = [IO.Path]::GetFullPath($Path)
  if (-not $Resolved.StartsWith($Allowed + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove test path outside $Allowed"
  }
  Remove-Item -LiteralPath $Resolved -Recurse -Force
}

