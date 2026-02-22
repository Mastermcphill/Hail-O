param(
  [string]$BaseUrl = 'https://hail-o-api-staging.onrender.com'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$headerPath = [System.IO.Path]::GetTempFileName()
$bodyPath = [System.IO.Path]::GetTempFileName()
try {
  & curl.exe -sS -D $headerPath -o $bodyPath "$BaseUrl/health"
  if ($LASTEXITCODE -ne 0) {
    throw "curl failed with exit code $LASTEXITCODE"
  }

  $headers = Get-Content $headerPath
  $statusLine = $headers | Where-Object { $_ -match '^HTTP/\S+\s+\d{3}' } | Select-Object -Last 1
  if (-not $statusLine) {
    throw "Unable to parse HTTP status for $BaseUrl/health"
  }
  $status = [int]([regex]::Match($statusLine, '\s(\d{3})\s').Groups[1].Value)
  $routingHeader = ($headers | Where-Object { $_ -match '^(?i)x-render-routing:\s*' } | Select-Object -Last 1)
  $routingValue = if ($routingHeader) { $routingHeader.Split(':', 2)[1].Trim() } else { '' }
  if ($routingValue -eq 'no-server') {
    throw 'Render provisioning incomplete: x-render-routing=no-server.'
  }
  if ($status -ne 200) {
    $raw = Get-Content $bodyPath -Raw
    throw "Unexpected /health HTTP status $status. Body: $raw"
  }

  $health = Get-Content $bodyPath -Raw | ConvertFrom-Json
  if (-not $health.ok -or -not $health.db_ok) {
    throw "Health check failed: ok=$($health.ok) db_ok=$($health.db_ok)"
  }

  $build = $health.build
  if ($null -eq $build) {
    throw '/health payload is missing build info.'
  }
  $runtime = [string]$build.runtime
  $runtimeMarker = [string]$build.runtime_marker
  $dartVersion = [string]$build.dart_version

  if ($runtime -ne 'dart_vm') {
    throw "Expected build.runtime=dart_vm, got '$runtime'"
  }
  if ($runtimeMarker -ne 'entrypoint_dart_ok') {
    throw "Expected build.runtime_marker=entrypoint_dart_ok, got '$runtimeMarker'"
  }
  if (-not $dartVersion.Contains('Dart SDK version')) {
    throw "Expected build.dart_version to include 'Dart SDK version', got '$dartVersion'"
  }

  Write-Output 'Render runtime sanity: PASS'
  Write-Output "runtime=$runtime marker=$runtimeMarker"
  Write-Output "dart_version=$dartVersion"
  Write-Output "x-render-routing=$routingValue"
} finally {
  if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
  if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
}
