function Get-FoundationRuntimeEnvironment {
  $Build = [Environment]::OSVersion.Version.Build
  $Windows = if ($Build -ge 22000) { '11' } elseif ($Build -ge 10240) { '10' } else { 'unsupported' }
  $PowerShell = if ($PSVersionTable.PSVersion.Major -eq 5) { '5.1' } else { '7' }
  $LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  $Candidates = New-Object Collections.Generic.List[string]
  $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
  if ($null -ne $CodexCommand -and -not [string]::IsNullOrWhiteSpace($CodexCommand.Source)) {
    $Candidates.Add([string]$CodexCommand.Source)
  }
  $Known = Join-Path $LocalAppData 'Programs\OpenAI\Codex\bin\codex.exe'
  if (Test-Path -LiteralPath $Known -PathType Leaf) { $Candidates.Add($Known) }
  $Version = $null
  foreach ($Candidate in $Candidates) {
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
    windows = $Windows
    powershell = $PowerShell
    codex_version = $Version
    codex_detected = ($null -ne $Version)
  }
}

function Invoke-FoundationEntry {
  param([AllowEmptyCollection()][string[]]$CliArgs)
  $UserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
  $LocalAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
  if ([string]::IsNullOrWhiteSpace($UserProfile) -or [string]::IsNullOrWhiteSpace($LocalAppData)) {
    [Console]::Error.WriteLine('UNSAFE_PATH :: Current-user folders were not resolved')
    return 10
  }
  $Environment = Get-FoundationRuntimeEnvironment
  return Invoke-FoundationCli $CliArgs $PSScriptRoot $UserProfile $LocalAppData $Environment
}

