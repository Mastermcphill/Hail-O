$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
  [switch]$IncludeProd
)

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $root
try {
  Write-Output '=== FAST LOCAL GATE (backend dart test) ==='
  Push-Location (Join-Path $root 'backend')
  try {
    dart test
    if ($LASTEXITCODE -ne 0) {
      throw "backend dart test failed with exit code $LASTEXITCODE"
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
