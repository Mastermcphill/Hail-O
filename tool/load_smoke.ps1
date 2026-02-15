$ErrorActionPreference = 'Stop'

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

$count = if ($env:LOAD_REQUESTS) { [int]$env:LOAD_REQUESTS } else { 200 }
$concurrency = if ($env:LOAD_CONCURRENCY) { [int]$env:LOAD_CONCURRENCY } else { 10 }
if ($count -le 0) { $count = 200 }
if ($concurrency -le 0) { $concurrency = 10 }

$jobs = @()
for ($i = 1; $i -le $count; $i++) {
  while ((Get-Job -State Running).Count -ge $concurrency) {
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

Write-Output "BASE_URL=$baseUrl"
Write-Output "LOAD_REQUESTS=$count"
Write-Output "LOAD_CONCURRENCY=$concurrency"
Write-Output 'STATUS_COUNTS:'
foreach ($group in $grouped) {
  Write-Output "$($group.Name): $($group.Count)"
}
