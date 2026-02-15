$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$envName = if ($env:ENV) { $env:ENV } else { 'staging' }
if ($env:HAILO_API_BASE_URL) {
  $baseUrl = $env:HAILO_API_BASE_URL
} elseif ($envName -eq 'production') {
  $baseUrl = 'https://hail-o-api.onrender.com'
} else {
  $baseUrl = 'https://hail-o-api-staging.onrender.com'
}

if ($baseUrl -eq 'https://hail-o-api.onrender.com' -and $env:HAILO_ALLOW_PROD_SMOKE -ne '1') {
  throw 'Refusing to run smoke against production without HAILO_ALLOW_PROD_SMOKE=1'
}

$runId = if ($env:HAILO_SMOKE_RUN_ID) { $env:HAILO_SMOKE_RUN_ID } else { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString() }
$password = if ($env:HAILO_SMOKE_PASSWORD) { $env:HAILO_SMOKE_PASSWORD } else { 'Passw0rd!' }
$riderEmail = "smoke.rider.$runId@hailo.dev"
$driverEmail = "smoke.driver.$runId@hailo.dev"
$adminEmail = $env:HAILO_ADMIN_EMAIL
$adminPassword = $env:HAILO_ADMIN_PASSWORD
$nowUtc = [DateTime]::UtcNow.ToString('o')

function New-IdempotencyKey {
  param([Parameter(Mandatory = $true)][string]$Step)
  return "smoke-$runId-$Step"
}

function Invoke-JsonRequest {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$JsonBody,
    [string]$Token,
    [string]$IdempotencyKey
  )

  $tmpPath = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmpPath, $JsonBody, $utf8NoBom)
    $curlArgs = @(
      '-sS',
      '-X', $Method,
      $Url,
      '-H', 'Content-Type: application/json'
    )
    if ($Token) {
      $curlArgs += @('-H', "Authorization: Bearer $Token")
    }
    if ($IdempotencyKey) {
      $curlArgs += @('-H', "Idempotency-Key: $IdempotencyKey")
    }
    $curlArgs += @('--data-binary', "@$tmpPath", '-w', "`nHTTP_STATUS:%{http_code}")
    $raw = (& curl.exe @curlArgs)
    $parsed = [regex]::Match($raw, '(?s)^(.*)\s*HTTP_STATUS:(\d{3})\s*$')
    if (-not $parsed.Success) {
      throw "Unable to parse HTTP status. Raw response: $raw"
    }
    $body = $parsed.Groups[1].Value
    $status = $parsed.Groups[2].Value
    $json = $null
    try {
      $json = $body | ConvertFrom-Json
    } catch {
      $json = $null
    }
    return @{
      Status = [int]$status
      Body = $body
      Json = $json
    }
  } finally {
    if (Test-Path $tmpPath) {
      Remove-Item $tmpPath -Force
    }
  }
}

function Assert-StatusIn {
  param(
    [Parameter(Mandatory = $true)][int]$Actual,
    [Parameter(Mandatory = $true)][int[]]$Expected
  )
  if ($Expected -notcontains $Actual) {
    throw "Unexpected HTTP status $Actual. Expected one of: $($Expected -join ', ')"
  }
}

Write-Output "BASE_URL=$baseUrl"
Write-Output "RUN_ID=$runId"

Write-Output "`n=== HEALTH ==="
curl.exe -sS -i "$baseUrl/health"

Write-Output "`n=== RIDER REGISTER ==="
$registerRider = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/register" `
    -JsonBody (@{
      email = $riderEmail
      password = $password
      role = 'rider'
      display_name = 'Smoke Rider'
      next_of_kin = @{
        full_name = 'Smoke NOK'
        phone = '+2348010000000'
        relationship = 'Sibling'
      }
    } | ConvertTo-Json -Compress) `
  -IdempotencyKey (New-IdempotencyKey -Step 'rider-register')
Assert-StatusIn -Actual $registerRider.Status -Expected @(200, 201)
$riderUserId = if ($registerRider.Json) { $registerRider.Json.user_id } else { '' }
Write-Output "status=$($registerRider.Status) rider_user_id=$riderUserId"

Write-Output "`n=== RIDER LOGIN ==="
$loginRider = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/login" `
  -JsonBody (@{
      email = $riderEmail
      password = $password
    } | ConvertTo-Json -Compress)
Assert-StatusIn -Actual $loginRider.Status -Expected @(200)
$riderToken = if ($loginRider.Json) { $loginRider.Json.token } else { '' }
if (-not $riderToken) {
  throw 'Missing rider token in login response'
}
Write-Output "status=$($loginRider.Status) rider_email=$riderEmail"

Write-Output "`n=== RIDER REQUEST RIDE ==="
$rideRequest = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/request" `
  -Token $riderToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'ride-request') `
  -JsonBody (@{
      scheduled_departure_at = $nowUtc
      trip_scope = 'intra_city'
      distance_meters = 12000
      duration_seconds = 1800
      luggage_count = 1
      vehicle_class = 'sedan'
      base_fare_minor = 100000
      premium_markup_minor = 5000
      connection_fee_minor = 5000
    } | ConvertTo-Json -Compress)
Assert-StatusIn -Actual $rideRequest.Status -Expected @(200, 201)
$rideId = if ($rideRequest.Json) { $rideRequest.Json.ride_id } else { '' }
if (-not $rideId) {
  throw "Missing ride_id from request ride response: $($rideRequest.Body)"
}
Write-Output "status=$($rideRequest.Status) ride_id=$rideId"

Write-Output "`n=== DRIVER REGISTER + LOGIN ==="
$registerDriver = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/register" `
  -JsonBody (@{
      email = $driverEmail
      password = $password
      role = 'driver'
      display_name = 'Smoke Driver'
    } | ConvertTo-Json -Compress) `
  -IdempotencyKey (New-IdempotencyKey -Step 'driver-register')
Assert-StatusIn -Actual $registerDriver.Status -Expected @(200, 201)
$driverUserId = if ($registerDriver.Json) { $registerDriver.Json.user_id } else { '' }
$loginDriver = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/login" `
  -JsonBody (@{
      email = $driverEmail
      password = $password
    } | ConvertTo-Json -Compress)
Assert-StatusIn -Actual $loginDriver.Status -Expected @(200)
$driverToken = if ($loginDriver.Json) { $loginDriver.Json.token } else { '' }
if (-not $driverToken) {
  throw 'Missing driver token in login response'
}
Write-Output "driver_user_id=$driverUserId login_status=$($loginDriver.Status)"

Write-Output "`n=== DRIVER ACCEPT RIDE + REPLAY ==="
$acceptKey = New-IdempotencyKey -Step 'ride-accept'
$acceptRide = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideId/accept" `
  -Token $driverToken `
  -IdempotencyKey $acceptKey `
  -JsonBody '{}'
Assert-StatusIn -Actual $acceptRide.Status -Expected @(200)
Write-Output "accept_status=$($acceptRide.Status) ride_id=$rideId"
$acceptReplay = Invoke-JsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideId/accept" `
  -Token $driverToken `
  -IdempotencyKey $acceptKey `
  -JsonBody '{}'
Assert-StatusIn -Actual $acceptReplay.Status -Expected @(200)
Write-Output "accept_replay_status=$($acceptReplay.Status)"

if ($adminEmail -and $adminPassword) {
  Write-Output "`n=== ADMIN LOGIN ==="
  $adminLogin = Invoke-JsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/auth/login" `
    -JsonBody (@{
        email = $adminEmail
        password = $adminPassword
      } | ConvertTo-Json -Compress)
  Assert-StatusIn -Actual $adminLogin.Status -Expected @(200)
  $adminToken = if ($adminLogin.Json) { $adminLogin.Json.token } else { '' }
  if (-not $adminToken) {
    throw 'Missing admin token in login response'
  }
  Write-Output "admin_login_status=$($adminLogin.Status)"

  Write-Output "`n=== DISPUTE OPEN + RESOLVE ==="
  $openDispute = Invoke-JsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/disputes" `
    -Token $adminToken `
    -IdempotencyKey (New-IdempotencyKey -Step 'dispute-open') `
    -JsonBody (@{
        ride_id = $rideId
        reason = 'smoke_test'
      } | ConvertTo-Json -Compress)
  Assert-StatusIn -Actual $openDispute.Status -Expected @(200, 201)
  $disputeId = if ($openDispute.Json) { $openDispute.Json.dispute_id } else { '' }
  Write-Output "dispute_open_status=$($openDispute.Status) dispute_id=$disputeId"
  if ($disputeId) {
    $resolveKey = New-IdempotencyKey -Step 'dispute-resolve'
    $resolveDispute = Invoke-JsonRequest `
      -Method 'POST' `
      -Url "$baseUrl/disputes/$disputeId/resolve" `
      -Token $adminToken `
      -IdempotencyKey $resolveKey `
      -JsonBody (@{
          refund_minor = 0
          resolution_note = 'smoke_resolve'
        } | ConvertTo-Json -Compress)
    Assert-StatusIn -Actual $resolveDispute.Status -Expected @(200)
    Write-Output "dispute_resolve_status=$($resolveDispute.Status)"
  }

  Write-Output "`n=== ADMIN REVERSAL + REPLAY CHECK ==="
  $reversalKey = New-IdempotencyKey -Step 'admin-reversal'
  $ledgerId = if ($env:HAILO_REVERSAL_LEDGER_ID) { [int]$env:HAILO_REVERSAL_LEDGER_ID } else { 999999999 }
  $reversalBody = @{
    original_ledger_id = $ledgerId
    reason = 'smoke_reversal'
  } | ConvertTo-Json -Compress
  $reversalFirst = Invoke-JsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/admin/reversal" `
    -Token $adminToken `
    -IdempotencyKey $reversalKey `
    -JsonBody $reversalBody
  $reversalReplay = Invoke-JsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/admin/reversal" `
    -Token $adminToken `
    -IdempotencyKey $reversalKey `
    -JsonBody $reversalBody
  Write-Output "reversal_status_first=$($reversalFirst.Status) reversal_status_replay=$($reversalReplay.Status)"
  if ($reversalFirst.Status -ne $reversalReplay.Status) {
    throw 'Reversal replay status mismatch'
  }
} else {
  Write-Output "`n=== ADMIN FLOW SKIPPED ==="
  Write-Output 'Set HAILO_ADMIN_EMAIL and HAILO_ADMIN_PASSWORD to run admin smoke flow.'
}

Write-Output "`nSmoke suite completed successfully."
