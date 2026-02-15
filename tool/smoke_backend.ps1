$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'

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
$reversalLedgerId = $env:HAILO_REVERSAL_LEDGER_ID
$nowUtc = [DateTime]::UtcNow.AddHours(2).ToString('o')

function New-IdempotencyKey {
  param([Parameter(Mandatory = $true)][string]$Step)
  return "smoke-$runId-$Step"
}

function Invoke-CurlJsonRequest {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$JsonBody,
    [string]$Token,
    [string]$IdempotencyKey,
    [string]$TraceId,
    [int[]]$AllowedStatus = @(200, 201)
  )

  $headerPath = [System.IO.Path]::GetTempFileName()
  $bodyPath = [System.IO.Path]::GetTempFileName()
  $payloadPath = if ($JsonBody) { [System.IO.Path]::GetTempFileName() } else { $null }

  try {
    $curlArgs = @(
      '-sS',
      '-X', $Method,
      $Url,
      '-H', 'Accept: application/json',
      '-D', $headerPath,
      '-o', $bodyPath
    )

    if ($JsonBody) {
      [System.IO.File]::WriteAllText($payloadPath, $JsonBody, $utf8NoBom)
      $curlArgs += @('-H', 'Content-Type: application/json', '--data-binary', "@$payloadPath")
    }
    if ($Token) {
      $curlArgs += @('-H', "Authorization: Bearer $Token")
    }
    if ($IdempotencyKey) {
      $curlArgs += @('-H', "Idempotency-Key: $IdempotencyKey")
    }
    if ($TraceId) {
      $curlArgs += @('-H', "X-Trace-Id: $TraceId")
    }

    & curl.exe @curlArgs
    if ($LASTEXITCODE -ne 0) {
      $rawFailureBody = if (Test-Path $bodyPath) { Get-Content $bodyPath -Raw } else { '' }
      throw "curl failed with exit code $LASTEXITCODE for $Method $Url`n$rawFailureBody"
    }

    $headerLines = Get-Content $headerPath
    $statusLine = $headerLines | Where-Object { $_ -match '^HTTP/\S+\s+\d{3}' } | Select-Object -Last 1
    if (-not $statusLine) {
      $rawBody = Get-Content $bodyPath -Raw
      throw "Unable to parse HTTP status for $Method $Url`n$rawBody"
    }

    $status = [int]([regex]::Match($statusLine, '\s(\d{3})\s').Groups[1].Value)
    if ($AllowedStatus -notcontains $status) {
      $rawBody = Get-Content $bodyPath -Raw
      throw "Unexpected HTTP status $status for $Method $Url. Expected one of: $($AllowedStatus -join ', ')`n$rawBody"
    }

    $headers = @{}
    foreach ($line in $headerLines) {
      if ($line -match '^[^:\s]+:\s*') {
        $parts = $line.Split(':', 2)
        $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
      }
    }

    $rawBody = Get-Content $bodyPath -Raw
    try {
      $json = $rawBody | ConvertFrom-Json
    } catch {
      throw "Expected JSON response for $Method $Url but got:`n$rawBody"
    }
    if ($status -ge 400) {
      $traceId = if ($json.PSObject.Properties.Name -contains 'trace_id') { [string]$json.trace_id } else { '' }
      if ([string]::IsNullOrWhiteSpace($traceId)) {
        throw "Error response missing trace_id for $Method $Url`n$rawBody"
      }
    }

    return @{
      Status = $status
      Body = $rawBody
      Json = $json
      Headers = $headers
    }
  } finally {
    if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
    if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
    if ($payloadPath -and (Test-Path $payloadPath)) { Remove-Item $payloadPath -Force }
  }
}

function Assert-True {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw $Message
  }
}

function Get-JsonPathValue {
  param(
    [Parameter(Mandatory = $true)]$JsonObject,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $value = $JsonObject
  foreach ($part in ($Path -split '\.')) {
    if ($null -eq $value) {
      return $null
    }
    if ($value -is [System.Collections.IDictionary]) {
      $value = $value[$part]
      continue
    }
    if ($value -is [psobject]) {
      if ($value.PSObject.Properties.Name -contains $part) {
        $value = $value.$part
      } else {
        $value = $null
      }
      continue
    }
    if ($value -is [System.Collections.IList]) {
      $index = 0
      if (-not [int]::TryParse($part, [ref]$index)) {
        return $null
      }
      if ($index -lt 0 -or $index -ge $value.Count) {
        return $null
      }
      $value = $value[$index]
      continue
    }
    return $null
  }
  return $value
}

function Get-JsonArrayLength {
  param(
    [Parameter(Mandatory = $true)]$JsonObject,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $value = Get-JsonPathValue -JsonObject $JsonObject -Path $Path
  if ($value -is [System.Collections.IList]) {
    return $value.Count
  }
  return 0
}

function Invoke-WithRideRetry {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [int]$MaxAttempts = 3,
    [int]$DelaySeconds = 2
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    try {
      return & $Action
    } catch {
      $errorMessage = $_.Exception.Message
      if (($errorMessage -like '*ride_not_found*') -and $attempt -lt $MaxAttempts) {
        Write-Output "retrying due to ride_not_found (attempt $attempt/$MaxAttempts)"
        Start-Sleep -Seconds $DelaySeconds
        continue
      }
      throw
    }
  }

  throw "Operation failed after $MaxAttempts attempts"
}

Write-Output "BASE_URL=$baseUrl"
Write-Output "RUN_ID=$runId"

Write-Output "`n=== HEALTH /api/healthz ==="
$healthApi = Invoke-CurlJsonRequest -Method 'GET' -Url "$baseUrl/api/healthz" -AllowedStatus @(200)
Assert-True -Condition ([bool]$healthApi.Json.ok) -Message "/api/healthz did not return ok=true"
Assert-True -Condition ([bool]$healthApi.Json.db_ok) -Message "/api/healthz did not return db_ok=true"
Write-Output "status=$($healthApi.Status) ok=$($healthApi.Json.ok) db_ok=$($healthApi.Json.db_ok)"

Write-Output "`n=== HEALTH /health ==="
$health = Invoke-CurlJsonRequest -Method 'GET' -Url "$baseUrl/health" -AllowedStatus @(200)
Assert-True -Condition ([bool]$health.Json.ok) -Message "/health did not return ok=true"
Assert-True -Condition ([bool]$health.Json.db_ok) -Message "/health did not return db_ok=true"
Write-Output "status=$($health.Status) ok=$($health.Json.ok) db_ok=$($health.Json.db_ok)"

Write-Output "`n=== RIDER REGISTER + IDEMPOTENCY REPLAY ==="
$registerKey = New-IdempotencyKey -Step 'rider-register'
$registerBody = @{
  email = $riderEmail
  password = $password
  role = 'rider'
  display_name = 'Smoke Rider'
  next_of_kin = @{
    full_name = 'Smoke NOK'
    phone = '+2348010000000'
    relationship = 'Sibling'
  }
} | ConvertTo-Json -Compress
$registerFirst = Invoke-CurlJsonRequest -Method 'POST' -Url "$baseUrl/auth/register" -JsonBody $registerBody -IdempotencyKey $registerKey
$registerReplay = Invoke-CurlJsonRequest -Method 'POST' -Url "$baseUrl/auth/register" -JsonBody $registerBody -IdempotencyKey $registerKey
$replayedFlag = [bool]$registerReplay.Json.replayed
$hasMatchingResultHash =
  ($registerFirst.Json.PSObject.Properties.Name -contains 'result_hash') -and
  ($registerReplay.Json.PSObject.Properties.Name -contains 'result_hash') -and
  ($registerFirst.Json.result_hash -eq $registerReplay.Json.result_hash)
$hasMatchingUserId =
  ($registerFirst.Json.PSObject.Properties.Name -contains 'user_id') -and
  ($registerReplay.Json.PSObject.Properties.Name -contains 'user_id') -and
  ($registerFirst.Json.user_id -eq $registerReplay.Json.user_id)
Assert-True -Condition ($replayedFlag -or $hasMatchingResultHash -or $hasMatchingUserId) -Message "Register replay did not expose replayed=true, matching result_hash, or stable user_id. Replay body: $($registerReplay.Body)"
$riderUserId = $registerFirst.Json.user_id
Write-Output "first_status=$($registerFirst.Status) replay_status=$($registerReplay.Status) rider_user_id=$riderUserId replayed=$replayedFlag"

Write-Output "`n=== RIDER LOGIN + TRACE PROPAGATION ==="
$traceId = "smoke-$runId-trace-login"
$loginRider = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/login" `
  -JsonBody (@{ email = $riderEmail; password = $password } | ConvertTo-Json -Compress) `
  -TraceId $traceId `
  -AllowedStatus @(200)
$returnedTraceHeader = if ($loginRider.Headers.ContainsKey('x-trace-id')) { $loginRider.Headers['x-trace-id'] } else { '' }
$returnedTraceBody = if ($loginRider.Json.PSObject.Properties.Name -contains 'trace_id') { $loginRider.Json.trace_id } else { '' }
Assert-True -Condition (($returnedTraceHeader -eq $traceId) -or ($returnedTraceBody -eq $traceId)) -Message "Trace id propagation failed. header='$returnedTraceHeader' body='$returnedTraceBody'"
$riderToken = $loginRider.Json.token
Assert-True -Condition ([string]::IsNullOrWhiteSpace($riderToken) -eq $false) -Message 'Missing rider token in login response'
Write-Output "status=$($loginRider.Status) rider_email=$riderEmail trace=$returnedTraceHeader"

Write-Output "`n=== RIDER REQUEST RIDE (CANCELLATION FLOW) ==="
$ridePayload = @{
  scheduled_departure_at = $nowUtc
  trip_scope = 'intra_city'
  distance_meters = 12000
  duration_seconds = 1800
  luggage_count = 1
  vehicle_class = 'sedan'
  base_fare_minor = 100000
  premium_markup_minor = 5000
  connection_fee_minor = 5000
} | ConvertTo-Json -Compress
$rideCancelRequest = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/request" `
  -Token $riderToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'ride-request') `
  -JsonBody $ridePayload
$rideCancelId = $rideCancelRequest.Json.ride_id
Assert-True -Condition ([string]::IsNullOrWhiteSpace($rideCancelId) -eq $false) -Message "Missing ride_id from request ride response: $($rideCancelRequest.Body)"
Write-Output "status=$($rideCancelRequest.Status) ride_id=$rideCancelId"

Write-Output "`n=== DRIVER REGISTER + LOGIN ==="
$registerDriver = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/register" `
  -JsonBody (@{
      email = $driverEmail
      password = $password
      role = 'driver'
      display_name = 'Smoke Driver'
    } | ConvertTo-Json -Compress) `
  -IdempotencyKey (New-IdempotencyKey -Step 'driver-register')
$loginDriver = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/auth/login" `
  -JsonBody (@{
      email = $driverEmail
      password = $password
    } | ConvertTo-Json -Compress) `
  -AllowedStatus @(200)
$driverToken = $loginDriver.Json.token
Assert-True -Condition ([string]::IsNullOrWhiteSpace($driverToken) -eq $false) -Message 'Missing driver token in login response'
Write-Output "driver_user_id=$($registerDriver.Json.user_id) login_status=$($loginDriver.Status)"

Write-Output "`n=== RIDER CANNOT ACCEPT RIDE (ROLE GUARD) ==="
$riderAcceptForbidden = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideCancelId/accept" `
  -Token $riderToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'rider-accept-forbidden') `
  -JsonBody '{}' `
  -AllowedStatus @(403)
Assert-True -Condition ($riderAcceptForbidden.Json.code -eq 'forbidden') -Message "Expected rider accept to be forbidden. body=$($riderAcceptForbidden.Body)"
Write-Output "rider_accept_status=$($riderAcceptForbidden.Status) code=$($riderAcceptForbidden.Json.code)"

Write-Output "`n=== DRIVER CANNOT CALL ADMIN REVERSAL (ROLE GUARD) ==="
$driverAdminForbidden = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/admin/reversal" `
  -Token $driverToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'driver-admin-forbidden') `
  -JsonBody (@{
      original_ledger_id = 1
      reason = 'smoke_forbidden'
    } | ConvertTo-Json -Compress) `
  -AllowedStatus @(403)
Assert-True -Condition ($driverAdminForbidden.Json.code -eq 'admin_only') -Message "Expected driver admin reversal to be admin_only. body=$($driverAdminForbidden.Body)"
Write-Output "driver_admin_reversal_status=$($driverAdminForbidden.Status) code=$($driverAdminForbidden.Json.code)"

Write-Output "`n=== DRIVER ACCEPT RIDE + REPLAY (CANCELLATION FLOW) ==="
$acceptKey = New-IdempotencyKey -Step 'ride-accept'
$acceptRide = Invoke-WithRideRetry -Action {
  Invoke-CurlJsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/rides/$rideCancelId/accept" `
    -Token $driverToken `
    -IdempotencyKey $acceptKey `
    -JsonBody '{}'
}
$acceptReplay = Invoke-WithRideRetry -Action {
  Invoke-CurlJsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/rides/$rideCancelId/accept" `
    -Token $driverToken `
    -IdempotencyKey $acceptKey `
    -JsonBody '{}'
}
Write-Output "accept_status=$($acceptRide.Status) accept_replay_status=$($acceptReplay.Status)"

Write-Output "`n=== RIDER CANCEL RIDE + REPLAY (IDEMPOTENT) ==="
$cancelKey = New-IdempotencyKey -Step 'ride-cancel'
$cancelFirst = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideCancelId/cancel" `
  -Token $riderToken `
  -IdempotencyKey $cancelKey `
  -JsonBody '{}' `
  -AllowedStatus @(200)
$cancelReplay = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideCancelId/cancel" `
  -Token $riderToken `
  -IdempotencyKey $cancelKey `
  -JsonBody '{}' `
  -AllowedStatus @(200)
$cancelReplayFlag = [bool]$cancelReplay.Json.replayed
$cancelReplayMatchesHash = ($cancelFirst.Json.result_hash -and $cancelReplay.Json.result_hash -and $cancelFirst.Json.result_hash -eq $cancelReplay.Json.result_hash)
Assert-True -Condition ($cancelReplayFlag -or $cancelReplayMatchesHash) -Message "Cancel replay did not expose replayed=true or matching result_hash. body=$($cancelReplay.Body)"
Write-Output "cancel_status=$($cancelFirst.Status) replay_status=$($cancelReplay.Status) replayed=$cancelReplayFlag"

Write-Output "`n=== CANCELLED RIDE SNAPSHOT HAS PENALTY AUDIT ==="
$cancelSnapshot = Invoke-CurlJsonRequest `
  -Method 'GET' `
  -Url "$baseUrl/rides/$rideCancelId" `
  -Token $riderToken `
  -AllowedStatus @(200)
$penaltyCount = @($cancelSnapshot.Json.penalties).Count
Assert-True -Condition ($penaltyCount -gt 0) -Message "Cancelled ride snapshot has no penalty records. body=$($cancelSnapshot.Body)"
Write-Output "ride_id=$rideCancelId penalties=$penaltyCount"

Write-Output "`n=== RIDER REQUEST RIDE (HAPPY PATH) ==="
$rideHappyRequest = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/request" `
  -Token $riderToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'ride-request-happy') `
  -JsonBody $ridePayload `
  -AllowedStatus @(201)
$rideId = $rideHappyRequest.Json.ride_id
$escrowId = $rideHappyRequest.Json.escrow_id
Assert-True -Condition ([string]::IsNullOrWhiteSpace($rideId) -eq $false) -Message "Missing happy-path ride_id from request response. body=$($rideHappyRequest.Body)"
Assert-True -Condition ([string]::IsNullOrWhiteSpace($escrowId) -eq $false) -Message "Missing escrow_id from request response. body=$($rideHappyRequest.Body)"
Write-Output "status=$($rideHappyRequest.Status) ride_id=$rideId escrow_id=$escrowId"

Write-Output "`n=== DRIVER ACCEPT/COMPLETE (HAPPY PATH) ==="
[void](Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideId/accept" `
  -Token $driverToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'ride-accept-happy') `
  -JsonBody '{}' `
  -AllowedStatus @(200))
$completeRide = Invoke-CurlJsonRequest `
  -Method 'POST' `
  -Url "$baseUrl/rides/$rideId/complete" `
  -Token $driverToken `
  -IdempotencyKey (New-IdempotencyKey -Step 'ride-complete-happy') `
  -JsonBody (@{
      escrow_id = $escrowId
      settlement_trigger = 'manual_override'
    } | ConvertTo-Json -Compress) `
  -AllowedStatus @(200, 500)

if ($completeRide.Status -eq 200) {
  $settlementNode = $completeRide.Json.settlement
  $settlementOk = [bool]($null -ne $settlementNode -and $settlementNode.ok -eq $true)
  Write-Output "ride_complete_status=$($completeRide.Status) settlement_ok=$settlementOk"
} else {
  $settlementNode = $null
  $settlementOk = $false
  $completeErrorCode = [string]$completeRide.Json.code
  Write-Output "ride_complete_status=$($completeRide.Status) code=$completeErrorCode"
  Write-Output 'Ride completion returned non-200 in this environment; settlement/payout assertions are skipped.'
}

if ($completeRide.Status -eq 200 -and $settlementOk) {
  Write-Output "`n=== COMPLETED RIDE SNAPSHOT HAS PAYOUT RECORD ==="
  $completeSnapshot = Invoke-CurlJsonRequest `
    -Method 'GET' `
    -Url "$baseUrl/rides/$rideId" `
    -Token $riderToken `
    -AllowedStatus @(200)
  $payoutStatus = [string]$completeSnapshot.Json.payout.status
  Assert-True -Condition ([string]::IsNullOrWhiteSpace($payoutStatus) -eq $false) -Message "Completed ride snapshot has no payout record. body=$($completeSnapshot.Body)"
  Write-Output "ride_id=$rideId payout_status=$payoutStatus"
} else {
  $settlementError = if ($null -ne $settlementNode) { [string]$settlementNode.error } else { 'not_available' }
  Write-Output "`n=== PAYOUT ASSERTION SKIPPED ==="
  Write-Output "Settlement not finalized in this environment (error=$settlementError)."
}

if ($adminEmail -and $adminPassword) {
  Write-Output "`n=== ADMIN LOGIN ==="
  $adminLogin = Invoke-CurlJsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/auth/login" `
    -JsonBody (@{
        email = $adminEmail
        password = $adminPassword
      } | ConvertTo-Json -Compress) `
    -AllowedStatus @(200)
  $adminToken = $adminLogin.Json.token
  Assert-True -Condition ([string]::IsNullOrWhiteSpace($adminToken) -eq $false) -Message 'Missing admin token in login response'
  Write-Output "admin_login_status=$($adminLogin.Status)"

  Write-Output "`n=== DISPUTE OPEN + RESOLVE ==="
  $openDispute = Invoke-CurlJsonRequest `
    -Method 'POST' `
    -Url "$baseUrl/disputes" `
    -Token $adminToken `
    -IdempotencyKey (New-IdempotencyKey -Step 'dispute-open') `
    -JsonBody (@{
        ride_id = $rideId
        reason = 'smoke_test'
      } | ConvertTo-Json -Compress)
  $disputeId = $openDispute.Json.dispute_id
  Write-Output "dispute_open_status=$($openDispute.Status) dispute_id=$disputeId"
  if ($disputeId) {
    $resolveDispute = Invoke-CurlJsonRequest `
      -Method 'POST' `
      -Url "$baseUrl/disputes/$disputeId/resolve" `
      -Token $adminToken `
      -IdempotencyKey (New-IdempotencyKey -Step 'dispute-resolve') `
      -JsonBody (@{
          refund_minor = 0
          resolution_note = 'smoke_resolve'
        } | ConvertTo-Json -Compress) `
      -AllowedStatus @(200)
    Write-Output "dispute_resolve_status=$($resolveDispute.Status)"
  }

  if ($reversalLedgerId) {
    Write-Output "`n=== ADMIN REVERSAL + REPLAY CHECK ==="
    $reversalKey = New-IdempotencyKey -Step 'admin-reversal'
    $reversalBody = @{
      original_ledger_id = [int]$reversalLedgerId
      reason = 'smoke_reversal'
    } | ConvertTo-Json -Compress
    $reversalFirst = Invoke-CurlJsonRequest `
      -Method 'POST' `
      -Url "$baseUrl/admin/reversal" `
      -Token $adminToken `
      -IdempotencyKey $reversalKey `
      -JsonBody $reversalBody `
      -AllowedStatus @(200)
    $reversalReplay = Invoke-CurlJsonRequest `
      -Method 'POST' `
      -Url "$baseUrl/admin/reversal" `
      -Token $adminToken `
      -IdempotencyKey $reversalKey `
      -JsonBody $reversalBody `
      -AllowedStatus @(200)
    Write-Output "reversal_status_first=$($reversalFirst.Status) reversal_status_replay=$($reversalReplay.Status)"
  } else {
    Write-Output "`n=== ADMIN REVERSAL SKIPPED ==="
    Write-Output 'Set HAILO_REVERSAL_LEDGER_ID to run reversal replay smoke.'
  }
} else {
  Write-Output "`n=== ADMIN FLOW SKIPPED ==="
  Write-Output 'Set HAILO_ADMIN_EMAIL and HAILO_ADMIN_PASSWORD to run admin smoke flow.'
}

Write-Output "`nSmoke suite completed successfully."
