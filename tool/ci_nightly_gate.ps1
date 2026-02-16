$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $root
try {
  $start = (Get-Date).ToUniversalTime().ToString('o')
  Write-Output "NIGHTLY_GATE_START $start"

  $stagingDatabaseUrl = [string]$env:HAILO_STAGING_DATABASE_URL
  if ([string]::IsNullOrWhiteSpace($stagingDatabaseUrl)) {
    throw 'Missing HAILO_STAGING_DATABASE_URL in CI worker env.'
  }

  $env:HAILO_ALLOW_DIRTY = '1'
  $env:HAILO_REQUIRE_RUNTIME_MARKER = '1'
  Remove-Item Env:HAILO_ALLOW_PROD_SMOKE -ErrorAction SilentlyContinue
  Remove-Item Env:HAILO_PROD_CONFIRM -ErrorAction SilentlyContinue

  $gateOutput = @(
    & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release_gate.ps1') 2>&1
  )
  $gateExitCode = $LASTEXITCODE

  foreach ($line in $gateOutput) {
    Write-Output $line
  }

  $artifactLine = @(
    $gateOutput |
      ForEach-Object { [string]$_ } |
      Where-Object { $_ -like 'artifact_dir=*' } |
      Select-Object -Last 1
  )

  $artifactDir = ''
  if ($artifactLine.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$artifactLine[0])) {
    $artifactDir = ([string]$artifactLine[0]).Substring('artifact_dir='.Length).Trim()
  } else {
    $opsRoot = Join-Path $root 'test_artifacts/ops'
    if (Test-Path $opsRoot) {
      $latest = Get-ChildItem -Path $opsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
      if ($null -ne $latest) {
        $artifactDir = $latest.FullName
      }
    }
  }

  if ([string]::IsNullOrWhiteSpace($artifactDir)) {
    $artifactDir = '<not_found>'
  }

  Write-Output "NIGHTLY_GATE_ARTIFACT_DIR $artifactDir"

  if ($gateExitCode -ne 0) {
    Write-Output 'NIGHTLY_GATE_RESULT FAIL'
    exit 1
  }

  Write-Output 'NIGHTLY_GATE_RESULT PASS'
  exit 0
} finally {
  Pop-Location
}
