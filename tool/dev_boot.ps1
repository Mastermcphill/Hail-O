param(
  [switch]$BackendOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$backendPath = Join-Path $repoRoot 'backend'

Write-Host 'Starting backend in a dedicated terminal...'
Start-Process powershell -ArgumentList @(
  '-NoExit',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  "Set-Location '$backendPath'; dart pub get; dart run main.dart"
)

if ($BackendOnly) {
  Write-Host 'Backend started. Flutter launch skipped (--BackendOnly).'
  exit 0
}

Write-Host 'Starting Flutter app in a dedicated terminal...'
Start-Process powershell -ArgumentList @(
  '-NoExit',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  "Set-Location '$repoRoot'; flutter pub get; flutter run --flavor dev"
)

Write-Host 'Dev stack launched (backend + flutter).'
