$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repoRoot 'backend'
$bundledDll = Join-Path $repoRoot 'backend\sqlite3.dll'
$rootDll = Join-Path $repoRoot 'sqlite3.dll'
$exitCode = 0

Push-Location $repoRoot
try {
  $hasPathDll = $false
  foreach ($segment in ($env:PATH -split ';')) {
    if ([string]::IsNullOrWhiteSpace($segment)) {
      continue
    }

    $candidate = Join-Path $segment 'sqlite3.dll'
    if (Test-Path $candidate) {
      $hasPathDll = $true
      break
    }
  }

  if (-not (Test-Path $rootDll) -and -not (Test-Path $bundledDll) -and -not $hasPathDll) {
    Write-Warning 'sqlite3.dll was not found. Install sqlite-tools and add sqlite3.dll to PATH, or place it in the repo root.'
  }

  flutter test -r expanded
  $exitCode = $LASTEXITCODE
}
finally {
  Pop-Location
}

if ($exitCode -ne 0) {
  exit $exitCode
}

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
