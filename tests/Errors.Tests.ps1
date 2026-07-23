It 'preserves a stable coded error' {
  $Caught = $null
  try { Throw-FoundationError -Code 'INVALID_PACKAGE' -Message 'bad package' }
  catch { $Caught = $_.Exception }
  Assert-Equal 'INVALID_PACKAGE' $Caught.Data['FoundationCode']
  Assert-Equal 'bad package' $Caught.Message
}

