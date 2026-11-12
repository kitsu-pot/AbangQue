$ErrorActionPreference = 'Stop'
$adminEmail = Read-Host 'Administrator email'
$adminPassword = Read-Host 'Password (15-128 characters)' -AsSecureString
$adminConfirmation = Read-Host 'Confirm password' -AsSecureString
$passwordPointer = [IntPtr]::Zero
$confirmationPointer = [IntPtr]::Zero
$savedEncoding = $OutputEncoding
try {
  $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminPassword)
  $confirmationPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminConfirmation)
  $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
  $plainConfirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($confirmationPointer)
  if ($plainPassword -cne $plainConfirmation) { throw 'Passwords do not match.' }
  $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  # Secrets travel through stdin, never command arguments, environment or files.
  @{ email = $adminEmail; password = $plainPassword } | ConvertTo-Json -Compress |
    & node --env-file=.env scripts/admin-provision.js
  $provisionExit = $LASTEXITCODE
} finally {
  if ($passwordPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer) }
  if ($confirmationPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($confirmationPointer) }
  $plainPassword = $null
  $plainConfirmation = $null
  $adminPassword.Dispose()
  $adminConfirmation.Dispose()
  $OutputEncoding = $savedEncoding
}
exit $provisionExit
