$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
  [string]$BaseUrl = $(if ($env:HAILO_API_BASE_URL) { $env:HAILO_API_BASE_URL } else { 'https://hail-o-api-staging.onrender.com' }),
  [string]$AdminToken = $env:HAILO_ADMIN_TOKEN
)

function Invoke-GetJson {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Token
  )

  $headerPath = [System.IO.Path]::GetTempFileName()
  $bodyPath = [System.IO.Path]::GetTempFileName()
  try {
    $args = @('-sS', '-D', $headerPath, '-o', $bodyPath, '-X', 'GET', $Url, '-H', 'Accept: application/json')
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
      $args += @('-H', "Authorization: Bearer $Token")
    }
    & curl.exe @args
    if ($LASTEXITCODE -ne 0) {
      throw "curl failed for $Url with exit code $LASTEXITCODE"
    }

    $statusLine = (Get-Content $headerPath | Where-Object { $_ -match '^HTTP/\S+\s+\d{3}' } | Select-Object -Last 1)
    $status = if ($statusLine) { [int]([regex]::Match($statusLine, '\s(\d{3})\s').Groups[1].Value) } else { 0 }
    $raw = Get-Content $bodyPath -Raw
    $json = $null
    try {
      $json = $raw | ConvertFrom-Json
    } catch {
      $json = $null
    }

    return @{
      status = $status
      raw = $raw
      json = $json
    }
  } finally {
    if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
    if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
  }
}

Write-Output "Incident snapshot base_url=$BaseUrl timestamp_utc=$([DateTime]::UtcNow.ToString('o'))"

$health = Invoke-GetJson -Url "$BaseUrl/health"
Write-Output "`n=== /health ==="
Write-Output "status=$($health.status)"
Write-Output $health.raw

$healthz = Invoke-GetJson -Url "$BaseUrl/api/healthz"
Write-Output "`n=== /api/healthz ==="
Write-Output "status=$($healthz.status)"
Write-Output $healthz.raw

if (-not [string]::IsNullOrWhiteSpace($AdminToken)) {
  $metrics = Invoke-GetJson -Url "$BaseUrl/metrics" -Token $AdminToken
  Write-Output "`n=== /metrics (admin token) ==="
  Write-Output "status=$($metrics.status)"
  Write-Output $metrics.raw
} else {
  Write-Output "`n=== /metrics ==="
  Write-Output 'SKIPPED: set HAILO_ADMIN_TOKEN to include authenticated metrics snapshot.'
}

if ($health.json -and $health.json.PSObject.Properties.Name -contains 'build') {
  $commit = [string]$health.json.build.commit
  $schema = [string]$health.json.build.db_schema
  $head = [string]$health.json.build.migration_head
  Write-Output "`n=== Build Snapshot ==="
  Write-Output "commit=$commit db_schema=$schema migration_head=$head"
}
