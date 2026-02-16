$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $root
try {
  $env:HAILO_ALLOW_DIRTY = '1'
  $env:HAILO_ALLOW_PROD_SMOKE = '0'
  Remove-Item Env:HAILO_PROD_CONFIRM -ErrorAction SilentlyContinue

  $gateOutput = @(& powershell -ExecutionPolicy Bypass -File .\tool\release_gate.ps1 2>&1)
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

  if ($artifactLine.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$artifactLine[0])) {
    $artifactDir = ([string]$artifactLine[0]).Substring('artifact_dir='.Length)
    Write-Output "nightly_artifact_dir=$artifactDir"
  } else {
    Write-Output 'nightly_artifact_dir=<not_found>'
  }

  exit $gateExitCode
} finally {
  Pop-Location
}
