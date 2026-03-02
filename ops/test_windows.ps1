$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$bundledDll = Join-Path $repoRoot 'backend\sqlite3.dll'
$rootDll = Join-Path $repoRoot 'sqlite3.dll'
$exitCode = 0

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

Push-Location $repoRoot
try {
  flutter test -r expanded
  $exitCode = $LASTEXITCODE
}
finally {
  Pop-Location
}

exit $exitCode
