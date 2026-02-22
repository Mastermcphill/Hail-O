$ErrorActionPreference = 'Stop'

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $root
try {
  Write-Output '=== BACKEND TESTS ==='
  Push-Location (Join-Path $root 'backend')
  try {
    dart test
    if ($LASTEXITCODE -ne 0) {
      throw "backend dart test failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  Write-Output '=== FLUTTER TESTS ==='
  flutter test
  if ($LASTEXITCODE -ne 0) {
    throw "flutter test failed with exit code $LASTEXITCODE"
  }

  Write-Output '=== STAGING SMOKE ==='
  if (-not $env:HAILO_API_BASE_URL) {
    $env:HAILO_API_BASE_URL = 'https://hail-o-api-staging.onrender.com'
  }
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "staging smoke failed with exit code $LASTEXITCODE"
  }

  if ($env:HAILO_ALLOW_PROD_SMOKE -eq '1') {
    Write-Output '=== PROD HEALTH SMOKE ==='
    curl.exe -sS -i 'https://hail-o-api.onrender.com/health'
    if ($LASTEXITCODE -ne 0) {
      throw "prod health smoke failed with exit code $LASTEXITCODE"
    }
  }

  Write-Output 'Release seal completed.'
} finally {
  Pop-Location
}
