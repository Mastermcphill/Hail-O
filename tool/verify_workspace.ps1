$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$current = Get-Location

Write-Output "Current location: $($current.Path)"
Write-Output "Expected repo root: $($root.Path)"

$required = @(
  'pubspec.yaml',
  'render.yaml',
  'backend',
  'tool'
)

$missing = @()
foreach ($entry in $required) {
  $path = Join-Path $root $entry
  if (-not (Test-Path $path)) {
    $missing += $entry
  }
}

if ($missing.Count -gt 0) {
  throw "Workspace verification failed. Missing repo markers: $($missing -join ', ')"
}

Write-Output 'Workspace verification: PASS'
Write-Output 'Recommended command sequence:'
Write-Output '1) powershell -ExecutionPolicy Bypass -File tool/verify_render_settings.ps1'
Write-Output '2) powershell -ExecutionPolicy Bypass -File tool/verify_staging_routing.ps1'
Write-Output '3) powershell -ExecutionPolicy Bypass -File tool/release_gate.ps1'
