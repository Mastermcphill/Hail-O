$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'

$envName = if ($env:ENV) { $env:ENV } else { 'staging' }
if ($env:HAILO_API_BASE_URL) {
  $baseUrl = $env:HAILO_API_BASE_URL
} elseif ($envName -eq 'production') {
  $baseUrl = 'https://hail-o-api.onrender.com'
} else {
  $baseUrl = 'https://hail-o-api-staging.onrender.com'
}

if ($baseUrl -eq 'https://hail-o-api.onrender.com' -and $env:HAILO_ALLOW_PROD_SMOKE -ne '1') {
  throw 'Refusing load smoke on production without HAILO_ALLOW_PROD_SMOKE=1'
}

$script:artifactDir = [string]$env:HAILO_LOAD_SMOKE_ARTIFACT_DIR
if (-not [string]::IsNullOrWhiteSpace($script:artifactDir)) {
  New-Item -ItemType Directory -Path $script:artifactDir -Force | Out-Null
}

function Save-LoadSmokeArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$FileName,
    [Parameter(Mandatory = $true)][string]$Content
  )

  if ([string]::IsNullOrWhiteSpace($script:artifactDir)) {
    return
  }
  $targetPath = Join-Path $script:artifactDir $FileName
  [System.IO.File]::WriteAllText($targetPath, $Content, [System.Text.Encoding]::UTF8)
}

$count = if ($env:LOAD_REQUESTS) { [int]$env:LOAD_REQUESTS } else { 200 }
$concurrency = if ($env:LOAD_CONCURRENCY) { [int]$env:LOAD_CONCURRENCY } else { 10 }
if ($count -le 0) { $count = 200 }
if ($concurrency -le 0) { $concurrency = 10 }

$jobs = @()
for ($i = 1; $i -le $count; $i++) {
  while (@(Get-Job -State Running).Count -ge $concurrency) {
    Start-Sleep -Milliseconds 50
  }

  $jobs += Start-Job -ArgumentList $baseUrl, $i -ScriptBlock {
    param($base, $idx)
    $mod = $idx % 3
    if ($mod -eq 0) {
      return [int](& curl.exe -sS -o NUL -w '%{http_code}' "$base/health")
    }
    if ($mod -eq 1) {
      return [int](& curl.exe -sS -o NUL -w '%{http_code}' `
          -X POST "$base/auth/login" `
          -H 'Content-Type: application/json' `
          --data '{"email":"load.invalid@hailo.dev","password":"invalid"}')
    }
    return [int](& curl.exe -sS -o NUL -w '%{http_code}' "$base/rides/load-smoke")
  }
}

$results = $jobs | Receive-Job -Wait -AutoRemoveJob
$grouped = $results | Group-Object | Sort-Object Name
$statusCounts = [ordered]@{}
foreach ($group in $grouped) {
  $statusCounts[[string]$group.Name] = [int]$group.Count
}

Write-Output "BASE_URL=$baseUrl"
Write-Output "LOAD_REQUESTS=$count"
Write-Output "LOAD_CONCURRENCY=$concurrency"
Write-Output 'STATUS_COUNTS:'
foreach ($group in $grouped) {
  Write-Output "$($group.Name): $($group.Count)"
}

Write-Output ''
Write-Output 'RATE_LIMIT_BURST_CHECK:'
$burstRequests = if ($env:LOAD_BURST_REQUESTS) {
  [int]$env:LOAD_BURST_REQUESTS
} elseif ($env:RATE_LIMIT_BURST) {
  [int]$env:RATE_LIMIT_BURST
} else {
  25
}
if ($burstRequests -le 0) { $burstRequests = 25 }
$enforceBurst = $env:HAILO_ENFORCE_RATE_LIMIT_BURST -eq '1'
$expectedEnabled = $null
if ($env:RATE_LIMIT_ENABLED -match '^(1|true)$') { $expectedEnabled = $true }
if ($env:RATE_LIMIT_ENABLED -match '^(0|false)$') { $expectedEnabled = $false }
$rateLimited = 0

for ($i = 1; $i -le $burstRequests; $i++) {
  $headerPath = [System.IO.Path]::GetTempFileName()
  $bodyPath = [System.IO.Path]::GetTempFileName()
  try {
    & curl.exe -sS -D $headerPath -o $bodyPath -w '%{http_code}' `
      -X POST "$baseUrl/auth/login" `
      -H 'Content-Type: application/json' `
      -H 'X-Forwarded-For: 203.0.113.10' `
      --data '{"email":"burst.invalid@hailo.dev","password":"invalid"}' | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "curl failed during rate-limit burst check with exit code $LASTEXITCODE"
    }

    $statusLine = (Get-Content $headerPath | Where-Object { $_ -match '^HTTP/\S+\s+\d{3}' } | Select-Object -Last 1)
    $status = if ($statusLine) { [int]([regex]::Match($statusLine, '\s(\d{3})\s').Groups[1].Value) } else { 0 }
    $rawBody = Get-Content $bodyPath -Raw
    Save-LoadSmokeArtifact -FileName ('burst_{0:D3}_{1}.json' -f $i, $status) -Content $rawBody

    if ($status -eq 429) {
      $json = $rawBody | ConvertFrom-Json
      if ($json.code -ne 'rate_limited') {
        throw "Expected code=rate_limited on burst 429. Body: $rawBody"
      }
      $traceId = [string]$json.trace_id
      if ([string]::IsNullOrWhiteSpace($traceId) -or $traceId -eq 'trace-unset') {
        throw "Expected non-empty trace_id on burst 429. Body: $rawBody"
      }
      $rateLimited++
    }
  } finally {
    if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
    if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
  }
}

Write-Output "BURST_REQUESTS=$burstRequests"
Write-Output "BURST_429_COUNT=$rateLimited"

$burstResult = 'PASS'
$burstMessage = 'RATE_LIMIT_BURST_CHECK=PASS (ENABLED)'
if ($rateLimited -gt 0) {
  if ($expectedEnabled -eq $false) {
    throw 'Observed 429 responses while RATE_LIMIT_ENABLED indicates disabled.'
  }
} else {
  if ($enforceBurst) {
    throw 'Expected at least one 429 from auth burst check but got none.'
  }
  if ($expectedEnabled -eq $true) {
    throw 'RATE_LIMIT_ENABLED is true but no 429 observed during burst check.'
  }
  $burstResult = 'SKIP'
  $burstMessage = 'RATE_LIMIT_BURST_CHECK=DISABLED (expected no 429)'
}
Write-Output $burstMessage

$summary = [ordered]@{
  generated_at = (Get-Date).ToString('o')
  base_url = $baseUrl
  load_requests = $count
  load_concurrency = $concurrency
  burst_requests = $burstRequests
  burst_429_count = $rateLimited
  burst_result = $burstResult
  enforce_burst = $enforceBurst
  expected_rate_limit_enabled = $expectedEnabled
  status_counts = $statusCounts
}
Save-LoadSmokeArtifact -FileName 'load_smoke_summary.json' -Content ($summary | ConvertTo-Json -Depth 8)

exit 0
