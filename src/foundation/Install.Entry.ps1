function Get-FoundationRuntimeEnvironment {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [ValidateSet('consumer', 'hub')][string]$InstallRole = 'consumer'
  )
  Assert-FoundationTarget $Target
  $Build = [Environment]::OSVersion.Version.Build
  $Windows = if ($Build -ge 22000) {
    '11'
  } elseif ($Build -ge 10240) {
    '10'
  } else {
    'unsupported'
  }
  $PowerShell = if ($PSVersionTable.PSVersion.Major -eq 5) { '5.1' } else { '7' }
  $LocalAppData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
  )
  $UserProfile = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::UserProfile
  )
  $CommandName = @{
    claude = 'claude'
    codex = 'codex'
    opencode = 'opencode'
  }[$Target]
  $Candidates = New-Object Collections.Generic.List[string]
  $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
  if ($null -ne $Command -and
      -not [string]::IsNullOrWhiteSpace([string]$Command.Source)) {
    $Candidates.Add([string]$Command.Source)
  }
  $Known = @{
    claude = @(
      (Join-Path $UserProfile '.local\bin\claude.exe'),
      (Join-Path $LocalAppData 'Programs\Claude\claude.exe')
    )
    codex = @(
      (Join-Path $LocalAppData 'Programs\OpenAI\Codex\bin\codex.exe'),
      (Join-Path $UserProfile '.local\bin\codex.exe')
    )
    opencode = @(
      (Join-Path $UserProfile '.opencode\bin\opencode.exe'),
      (Join-Path $UserProfile '.local\bin\opencode.exe')
    )
  }[$Target]
  foreach ($Path in @($Known)) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $Candidates.Add($Path) }
  }
  $Version = $null
  foreach ($Candidate in @($Candidates | Select-Object -Unique)) {
    try {
      $Info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Candidate)
      $Raw = if (-not [string]::IsNullOrWhiteSpace($Info.ProductVersion)) {
        $Info.ProductVersion
      } else {
        $Info.FileVersion
      }
      if ([string]$Raw -match '([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)') {
        $Version = $Matches[1]
        break
      }
    } catch {
      continue
    }
  }
  return [pscustomobject][ordered]@{
    target = $Target
    install_role = $InstallRole
    windows = $Windows
    powershell = $PowerShell
    client_version = $Version
    client_detected = ($null -ne $Version)
  }
}

function Get-FoundationEntryOption {
  param(
    [AllowEmptyCollection()][string[]]$CliArgs,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $Found = @()
  for ($Index = 1; $Index -lt @($CliArgs).Count; $Index++) {
    if ([string]$CliArgs[$Index] -ceq $Name -and $Index + 1 -lt $CliArgs.Count) {
      $Found += [string]$CliArgs[$Index + 1]
    }
  }
  if ($Found.Count -gt 1) {
    Throw-FoundationError -Code 'INVALID_PACKAGE' -Message "Duplicate option: $Name"
  }
  if ($Found.Count -eq 1) { return $Found[0] }
  return $null
}

function Invoke-FoundationEntry {
  param([AllowEmptyCollection()][string[]]$CliArgs)
  $UserProfile = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::UserProfile
  )
  $LocalAppData = [Environment]::GetFolderPath(
    [Environment+SpecialFolder]::LocalApplicationData
  )
  if ([string]::IsNullOrWhiteSpace($UserProfile) -or
      [string]::IsNullOrWhiteSpace($LocalAppData)) {
    [Console]::Error.WriteLine('UNSAFE_PATH :: Current-user folders were not resolved')
    return 10
  }
  try {
    $Manifest = Read-FoundationManifest (
      Join-Path $PSScriptRoot 'release-manifest.json'
    )
    $RequestedTarget = Get-FoundationEntryOption $CliArgs '-Target'
    $Target = if ([string]::IsNullOrWhiteSpace($RequestedTarget)) {
      [string]$Manifest.target
    } else {
      $RequestedTarget.ToLowerInvariant()
    }
    $RequestedRole = Get-FoundationEntryOption $CliArgs '-Role'
    $Role = if ([string]::IsNullOrWhiteSpace($RequestedRole)) {
      [string]$Manifest.sync_policy.default_role
    } else {
      $RequestedRole.ToLowerInvariant()
    }
    Assert-FoundationTarget $Target
    Assert-FoundationInstallRole $Role
    $Environment = Get-FoundationRuntimeEnvironment $Target $Role
    return Invoke-FoundationCli $CliArgs $PSScriptRoot $UserProfile `
      $LocalAppData $Environment
  } catch {
    $Code = [string]$_.Exception.Data['FoundationCode']
    if ([string]::IsNullOrWhiteSpace($Code)) { $Code = 'INVALID_PACKAGE' }
    [Console]::Error.WriteLine("$Code :: $($_.Exception.Message)")
    return Get-FoundationExitCode $Code
  }
}
