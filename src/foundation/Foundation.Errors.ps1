function Throw-FoundationError {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message
  )
  $Exception = [InvalidOperationException]::new($Message)
  $Exception.Data['FoundationCode'] = $Code
  throw $Exception
}

function Get-FoundationExitCode {
  param([AllowEmptyString()][string]$Code)
  switch ($Code) {
    'INVALID_PACKAGE' { return 2 }
    'BLOCKED_APPROVED_FOUNDATION_SOURCE' { return 2 }
    'UNSUPPORTED_ENVIRONMENT' { return 10 }
    'USER_CONFLICT' { return 10 }
    'UNSAFE_PATH' { return 10 }
    'DEPENDENCY_QUARANTINE' { return 10 }
    'RECOVERY_REQUIRED' { return 20 }
    'ACTIVE_DRIFT' { return 30 }
    'ROLLBACK_CONFLICT' { return 40 }
    default { return 2 }
  }
}

