$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

param(
  [string]$BaseUrl = 'https://hail-o-api-staging.onrender.com'
)

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
    throw "Unable to parse staging health status line."
  }
  $status = [int]([regex]::Match($statusLine, '\s(\d{3})\s').Groups[1].Value)
  $routingHeader = ($headers | Where-Object { $_ -match '^(?i)x-render-routing:\s*' } | Select-Object -Last 1)
  $routingValue = if ($routingHeader) { $routingHeader.Split(':', 2)[1].Trim() } else { '' }

  if ($routingValue -eq 'no-server') {
    throw 'Render provisioning incomplete: staging route is not attached to a running server (x-render-routing: no-server).'
  }
  if ($status -ne 200) {
    $raw = Get-Content $bodyPath -Raw
    throw "Staging /health returned HTTP $status. Body: $raw"
  }

  $body = Get-Content $bodyPath -Raw | ConvertFrom-Json
  if (-not $body.ok -or -not $body.db_ok) {
    throw "Staging /health is not healthy: ok=$($body.ok) db_ok=$($body.db_ok)"
  }

  Write-Output "Staging routing verification: PASS (status=$status, x-render-routing=$routingValue)"
} finally {
  if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
  if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
}
