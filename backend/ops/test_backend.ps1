$ErrorActionPreference = 'Stop'

$backendRoot = Split-Path -Parent $PSScriptRoot
$exitCode = 0

Push-Location $backendRoot
try {
  dart pub get
  if ($LASTEXITCODE -eq 0) {
    dart test -r expanded
  }
  $exitCode = $LASTEXITCODE
}
finally {
  Pop-Location
}

exit $exitCode
