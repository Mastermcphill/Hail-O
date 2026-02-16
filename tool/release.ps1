$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
  [switch]$IncludeProd,
  [switch]$IncludeLoadSmoke,
  [switch]$StrictLoadSmoke
)

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $root
try {
  Write-Output '=== WORKSPACE VERIFICATION ==='
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_workspace.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "workspace verification failed with exit code $LASTEXITCODE"
  }

  Write-Output '=== FAST LOCAL GATE (backend pub get + analyze + test + contract) ==='
  Push-Location (Join-Path $root 'backend')
  try {
    dart pub get
    if ($LASTEXITCODE -ne 0) {
      throw "backend dart pub get failed with exit code $LASTEXITCODE"
    }
    dart analyze
    if ($LASTEXITCODE -ne 0) {
      throw "backend dart analyze failed with exit code $LASTEXITCODE"
    }
    dart test
    if ($LASTEXITCODE -ne 0) {
      throw "backend dart test failed with exit code $LASTEXITCODE"
    }
    dart run tool/check_contract_breaking.dart
    if ($LASTEXITCODE -ne 0) {
      throw "backend contract check failed with exit code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  Write-Output '=== STAGING RELEASE GATE ==='
  $env:HAILO_ALLOW_PROD_SMOKE = '0'
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release_gate.ps1')
  if ($LASTEXITCODE -ne 0) {
    throw "staging release gate failed with exit code $LASTEXITCODE"
  }

  if ($IncludeLoadSmoke) {
    Write-Output '=== STAGING LOAD SMOKE ==='
    $env:HAILO_API_BASE_URL = 'https://hail-o-api-staging.onrender.com'
    $env:ENV = 'staging'
    if ($StrictLoadSmoke) {
      $env:HAILO_ENFORCE_RATE_LIMIT_BURST = '1'
    } else {
      $env:HAILO_ENFORCE_RATE_LIMIT_BURST = '0'
    }
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'load_smoke.ps1')
    if ($LASTEXITCODE -ne 0) {
      if ($StrictLoadSmoke) {
        throw "strict staging load smoke failed with exit code $LASTEXITCODE"
      }
      Write-Output "WARN: staging load smoke failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Output '=== STAGING LOAD SMOKE SKIPPED ==='
    Write-Output 'Run with -IncludeLoadSmoke to execute load smoke.'
  }

  if ($IncludeProd) {
    Write-Output '=== PRODUCTION RELEASE GATE ==='
    $env:HAILO_ALLOW_PROD_SMOKE = '1'
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release_gate.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "production release gate failed with exit code $LASTEXITCODE"
    }
  } else {
    Write-Output '=== PRODUCTION GATE SKIPPED ==='
    Write-Output 'Run with -IncludeProd to execute production smoke gate.'
  }

  Write-Output 'Release workflow completed successfully.'
} finally {
  Pop-Location
}
