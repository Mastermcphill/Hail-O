param(
  [string]$BaseUrl = "",
  [string]$EnvName = "",
  [string]$PhoneE164 = "",
  [string]$OtpCode = "",
  [string]$AccessToken = "",
  [string]$AdminToken = "",
  [string]$WebhookSecret = "",
  [string]$PaystackSecret = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = $env:BASE_URL
}
if ([string]::IsNullOrWhiteSpace($EnvName)) {
  $EnvName = if ($env:ENV) { $env:ENV } else { "staging" }
}
if ([string]::IsNullOrWhiteSpace($PhoneE164)) {
  $PhoneE164 = if ($env:E2E_PHONE_E164) { $env:E2E_PHONE_E164 } else { "+15550001111" }
}
if ([string]::IsNullOrWhiteSpace($OtpCode)) {
  $OtpCode = if ($env:E2E_OTP_CODE) { $env:E2E_OTP_CODE } else { "000000" }
}
if ([string]::IsNullOrWhiteSpace($AccessToken)) {
  $AccessToken = $env:E2E_ACCESS_TOKEN
}
if ([string]::IsNullOrWhiteSpace($AdminToken)) {
  $AdminToken = if ($env:E2E_ADMIN_TOKEN) { $env:E2E_ADMIN_TOKEN } else { $env:ADMIN_TOKEN }
}
if ([string]::IsNullOrWhiteSpace($WebhookSecret)) {
  $WebhookSecret = if ($env:E2E_WEBHOOK_SECRET) { $env:E2E_WEBHOOK_SECRET } else { $env:PAYMENTS_WEBHOOK_SECRET }
}
if ([string]::IsNullOrWhiteSpace($PaystackSecret)) {
  if ($env:E2E_PAYSTACK_SECRET) {
    $PaystackSecret = $env:E2E_PAYSTACK_SECRET
  } elseif ($env:PAYSTACK_WEBHOOK_SECRET) {
    $PaystackSecret = $env:PAYSTACK_WEBHOOK_SECRET
  } else {
    $PaystackSecret = $env:PAYSTACK_SECRET_KEY
  }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  throw "BaseUrl is required. Example: .\\smoke_e2e.ps1 -BaseUrl https://staging.example.com"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$artifactRoot = Join-Path $scriptDir "test_artifacts/e2e"
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$runDir = Join-Path $artifactRoot $runStamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$steps = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]
$traceIds = New-Object System.Collections.Generic.List[string]
$failFast = $false

function Add-Step {
  param(
    [string]$Name,
    [bool]$Ok,
    [string]$Status,
    [int]$DurationMs,
    [string]$TraceId,
    [string]$Artifact,
    [string]$Detail
  )

  $entry = [ordered]@{
    name = $Name
    ok = $Ok
    status = $Status
    duration_ms = $DurationMs
    trace_id = $TraceId
    artifact = $Artifact
    detail = $Detail
  }
  $steps.Add($entry)
  if (-not [string]::IsNullOrWhiteSpace($TraceId)) {
    $traceIds.Add($TraceId)
  }
  if (-not $Ok) {
    $failures.Add([ordered]@{
      name = $Name
      status = $Status
      trace_id = $TraceId
      detail = $Detail
    })
  }
}

function Invoke-SmokeRequest {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body,
    [hashtable]$Headers
  )

  $uri = [Uri]::new($BaseUrl.TrimEnd('/') + $Path)
  $requestHeaders = @{
    Accept = "application/json"
    "x-trace-id" = "smoke-" + [guid]::NewGuid().ToString("N")
  }
  foreach ($kv in $Headers.GetEnumerator()) {
    $requestHeaders[$kv.Key] = $kv.Value
  }

  $statusCode = 0
  $content = ""
  try {
    if ($null -ne $Body) {
      $jsonBody = ($Body | ConvertTo-Json -Depth 10 -Compress)
      $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $requestHeaders -ContentType "application/json" -Body $jsonBody
    } else {
      $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $requestHeaders
    }
    $statusCode = [int]$response.StatusCode
    $content = "$($response.Content)"
  } catch {
    $webResponse = $_.Exception.Response
    if ($null -eq $webResponse) {
      throw
    }
    $statusCode = [int]$webResponse.StatusCode
    try {
      $stream = $webResponse.GetResponseStream()
      if ($null -ne $stream) {
        $reader = New-Object System.IO.StreamReader($stream)
        $content = $reader.ReadToEnd()
        $reader.Dispose()
      }
    } catch {
      $content = ""
    }
  }

  $payload = $null
  if (-not [string]::IsNullOrWhiteSpace($content)) {
    try {
      $payload = $content | ConvertFrom-Json -Depth 30
    } catch {
      $payload = [ordered]@{ raw = $content }
    }
  }

  return [ordered]@{
    status = $statusCode
    payload = $payload
    raw = $content
  }
}

function Save-Artifact {
  param([string]$Name, [object]$Object)
  $path = Join-Path $runDir $Name
  ($Object | ConvertTo-Json -Depth 30) | Set-Content -Path $path
  return $path
}

function Assert-Status {
  param(
    [string]$StepName,
    [int[]]$Expected,
    [int]$Actual,
    [datetime]$StartedAt,
    [object]$Payload,
    [string]$ArtifactName,
    [string]$Detail = ""
  )

  $durationMs = [int]([DateTime]::UtcNow - $StartedAt).TotalMilliseconds
  $traceId = ""
  if ($null -ne $Payload -and $null -ne $Payload.trace_id) {
    $traceId = "$($Payload.trace_id)"
  }
  $ok = $Expected -contains $Actual
  Add-Step -Name $StepName -Ok $ok -Status "$Actual" -DurationMs $durationMs -TraceId $traceId -Artifact $ArtifactName -Detail $Detail
  if (-not $ok) {
    $script:failFast = $true
  }
  return $ok
}

Write-Host "[smoke] base=$BaseUrl env=$EnvName"
Write-Host "[smoke] artifacts=$runDir"

# Flow A auth
if ([string]::IsNullOrWhiteSpace($AccessToken)) {
  $started = [DateTime]::UtcNow
  $otpReq = Invoke-SmokeRequest -Method "POST" -Path "/auth/otp/request" -Body @{ phone_e164 = $PhoneE164 } -Headers @{}
  $artifact = Save-Artifact -Name "01_auth_otp_request.json" -Object $otpReq.payload
  [void](Assert-Status -StepName "auth.otp_request" -Expected @(200) -Actual $otpReq.status -StartedAt $started -Payload $otpReq.payload -ArtifactName (Split-Path $artifact -Leaf))

  if (-not $failFast) {
    $started = [DateTime]::UtcNow
    $otpVerify = Invoke-SmokeRequest -Method "POST" -Path "/auth/otp/verify" -Body @{ phone_e164 = $PhoneE164; code = $OtpCode } -Headers @{}
    $artifact = Save-Artifact -Name "02_auth_otp_verify.json" -Object $otpVerify.payload
    [void](Assert-Status -StepName "auth.otp_verify" -Expected @(200) -Actual $otpVerify.status -StartedAt $started -Payload $otpVerify.payload -ArtifactName (Split-Path $artifact -Leaf))

    if (-not $failFast) {
      $AccessToken = "$($otpVerify.payload.access_token)"
      if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        $AccessToken = "$($otpVerify.payload.data.access_token)"
      }
      $refreshToken = "$($otpVerify.payload.refresh_token)"
      if ([string]::IsNullOrWhiteSpace($refreshToken)) {
        $refreshToken = "$($otpVerify.payload.data.refresh_token)"
      }
      if ([string]::IsNullOrWhiteSpace($AccessToken)) {
        Add-Step -Name "auth.extract_token" -Ok $false -Status "parse_error" -DurationMs 0 -TraceId "" -Artifact "02_auth_otp_verify.json" -Detail "access_token missing"
        $failFast = $true
      } else {
        Add-Step -Name "auth.extract_token" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "02_auth_otp_verify.json" -Detail "token acquired"
      }

      if (-not $failFast -and -not [string]::IsNullOrWhiteSpace($refreshToken)) {
        $started = [DateTime]::UtcNow
        $refresh = Invoke-SmokeRequest -Method "POST" -Path "/auth/token/refresh" -Body @{ refresh_token = $refreshToken } -Headers @{ Authorization = "Bearer $AccessToken" }
        $artifact = Save-Artifact -Name "03_auth_refresh.json" -Object $refresh.payload
        [void](Assert-Status -StepName "auth.refresh" -Expected @(200) -Actual $refresh.status -StartedAt $started -Payload $refresh.payload -ArtifactName (Split-Path $artifact -Leaf))
      }
    }
  }
} else {
  Add-Step -Name "auth.preprovisioned_token" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "" -Detail "using provided E2E_ACCESS_TOKEN"
}

$offerId = ""
$purchaseId = ""
$tripId = ""
$driverId = ""

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $offers = Invoke-SmokeRequest -Method "GET" -Path "/marketplace/offers" -Body $null -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "04_marketplace_offers.json" -Object $offers.payload
  [void](Assert-Status -StepName "marketplace.offers" -Expected @(200) -Actual $offers.status -StartedAt $started -Payload $offers.payload -ArtifactName (Split-Path $artifact -Leaf))

  if (-not $failFast) {
    if ($offers.payload.data -and $offers.payload.data.Count -gt 0) {
      $offerId = "$($offers.payload.data[0].id)"
    }
    if ([string]::IsNullOrWhiteSpace($offerId)) {
      Add-Step -Name "marketplace.pick_offer" -Ok $false -Status "parse_error" -DurationMs 0 -TraceId "" -Artifact "04_marketplace_offers.json" -Detail "no offer id found"
      $failFast = $true
    } else {
      Add-Step -Name "marketplace.pick_offer" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "04_marketplace_offers.json" -Detail "offer_id=$offerId"
    }
  }
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $idem = "smoke-purchase-" + [guid]::NewGuid().ToString("N")
  $purchase = Invoke-SmokeRequest -Method "POST" -Path "/marketplace/purchases" -Body @{ offer_id = $offerId; quantity = 1 } -Headers @{ Authorization = "Bearer $AccessToken"; "idempotency-key" = $idem }
  $artifact = Save-Artifact -Name "05_marketplace_purchase_create.json" -Object $purchase.payload
  [void](Assert-Status -StepName "marketplace.purchase_create" -Expected @(200,201) -Actual $purchase.status -StartedAt $started -Payload $purchase.payload -ArtifactName (Split-Path $artifact -Leaf))

  if (-not $failFast) {
    $purchaseId = "$($purchase.payload.data.purchase.purchase_id)"
    if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = "$($purchase.payload.data.purchase_id)" }
    if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = "$($purchase.payload.purchase.purchase_id)" }
    if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = "$($purchase.payload.purchase_id)" }

    if ([string]::IsNullOrWhiteSpace($purchaseId)) {
      Add-Step -Name "marketplace.extract_purchase_id" -Ok $false -Status "parse_error" -DurationMs 0 -TraceId "" -Artifact "05_marketplace_purchase_create.json" -Detail "purchase id missing"
      $failFast = $true
    } else {
      Add-Step -Name "marketplace.extract_purchase_id" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "05_marketplace_purchase_create.json" -Detail "purchase_id=$purchaseId"
    }
  }
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $intent = Invoke-SmokeRequest -Method "POST" -Path "/payments/intents" -Body @{ purchase_id = $purchaseId } -Headers @{ Authorization = "Bearer $AccessToken"; "idempotency-key" = ("smoke-intent-" + [guid]::NewGuid().ToString("N")) }
  $artifact = Save-Artifact -Name "06_payments_intent_create.json" -Object $intent.payload
  [void](Assert-Status -StepName "payments.intent_create" -Expected @(200) -Actual $intent.status -StartedAt $started -Payload $intent.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $eventId = "evt-smoke-" + [guid]::NewGuid().ToString("N")
  $payloadObj = [ordered]@{
    provider_event_id = $eventId
    event_type = "payment_succeeded"
    purchase_id = $purchaseId
    event = "charge.success"
    data = [ordered]@{
      id = $eventId
      metadata = [ordered]@{ purchase_id = $purchaseId }
    }
  }
  $payloadJson = $payloadObj | ConvertTo-Json -Depth 10 -Compress
  $headers = @{ Authorization = "Bearer $AccessToken" }
  if (-not [string]::IsNullOrWhiteSpace($WebhookSecret)) {
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($WebhookSecret)
    $sigBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadJson))
    $sig = -join ($sigBytes | ForEach-Object { $_.ToString("x2") })
    $headers["x-webhook-signature"] = $sig
  }
  if (-not [string]::IsNullOrWhiteSpace($PaystackSecret)) {
    $hmac = New-Object System.Security.Cryptography.HMACSHA512
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($PaystackSecret)
    $sigBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadJson))
    $sig = -join ($sigBytes | ForEach-Object { $_.ToString("x2") })
    $headers["x-paystack-signature"] = $sig
    $headers["x-paystack-event-id"] = $eventId
  }

  $started = [DateTime]::UtcNow
  $webhook = Invoke-SmokeRequest -Method "POST" -Path "/webhooks/payments" -Body $payloadObj -Headers $headers
  $artifact = Save-Artifact -Name "07_payments_webhook.json" -Object $webhook.payload
  [void](Assert-Status -StepName "payments.webhook_simulate" -Expected @(200) -Actual $webhook.status -StartedAt $started -Payload $webhook.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $purchaseGet = Invoke-SmokeRequest -Method "GET" -Path "/marketplace/purchases/$purchaseId" -Body $null -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "08_marketplace_purchase_get.json" -Object $purchaseGet.payload
  [void](Assert-Status -StepName "marketplace.purchase_get" -Expected @(200) -Actual $purchaseGet.status -StartedAt $started -Payload $purchaseGet.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $quote = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/quote" -Body @{ pickup = @{ lat = 6.455; lng = 3.384 }; dropoff = @{ lat = 6.6018; lng = 3.3515 }; service_level = "standard" } -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "09_dispatch_quote.json" -Object $quote.payload
  [void](Assert-Status -StepName "dispatch.quote" -Expected @(200) -Actual $quote.status -StartedAt $started -Payload $quote.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $tripCreate = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips" -Body @{ pickup = @{ lat = 6.455; lng = 3.384; address = "Lagos Island" }; dropoff = @{ lat = 6.6018; lng = 3.3515; address = "Ikeja" }; notes = "smoke run" } -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "10_dispatch_trip_create.json" -Object $tripCreate.payload
  [void](Assert-Status -StepName "dispatch.trip_create" -Expected @(201) -Actual $tripCreate.status -StartedAt $started -Payload $tripCreate.payload -ArtifactName (Split-Path $artifact -Leaf))
  if (-not $failFast) {
    $tripId = "$($tripCreate.payload.trip.id)"
    if ([string]::IsNullOrWhiteSpace($tripId)) {
      Add-Step -Name "dispatch.extract_trip_id" -Ok $false -Status "parse_error" -DurationMs 0 -TraceId "" -Artifact "10_dispatch_trip_create.json" -Detail "trip id missing"
      $failFast = $true
    } else {
      Add-Step -Name "dispatch.extract_trip_id" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "10_dispatch_trip_create.json" -Detail "trip_id=$tripId"
    }
  }
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $status = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/status" -Body @{ status = "searching" } -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "11_dispatch_status_searching.json" -Object $status.payload
  [void](Assert-Status -StepName "dispatch.status_searching" -Expected @(200) -Actual $status.status -StartedAt $started -Payload $status.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $driverRun = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $driverEmail = "smoke.driver.$driverRun@hailo.dev"
  $driverPass = "Passw0rd!"

  $started = [DateTime]::UtcNow
  $driverRegister = Invoke-SmokeRequest -Method "POST" -Path "/auth/register" -Body @{ email = $driverEmail; password = $driverPass; role = "driver"; display_name = "Smoke Driver" } -Headers @{ "idempotency-key" = "smoke-driver-$driverRun" }
  $artifact = Save-Artifact -Name "12_dispatch_driver_register.json" -Object $driverRegister.payload
  [void](Assert-Status -StepName "dispatch.driver_register" -Expected @(201) -Actual $driverRegister.status -StartedAt $started -Payload $driverRegister.payload -ArtifactName (Split-Path $artifact -Leaf))

  if (-not $failFast) {
    $started = [DateTime]::UtcNow
    $driverLogin = Invoke-SmokeRequest -Method "POST" -Path "/auth/login" -Body @{ email = $driverEmail; password = $driverPass } -Headers @{}
    $artifact = Save-Artifact -Name "13_dispatch_driver_login.json" -Object $driverLogin.payload
    [void](Assert-Status -StepName "dispatch.driver_login" -Expected @(200) -Actual $driverLogin.status -StartedAt $started -Payload $driverLogin.payload -ArtifactName (Split-Path $artifact -Leaf))
    if (-not $failFast) {
      $driverId = "$($driverLogin.payload.user_id)"
      if ([string]::IsNullOrWhiteSpace($driverId)) {
        Add-Step -Name "dispatch.extract_driver_id" -Ok $false -Status "parse_error" -DurationMs 0 -TraceId "" -Artifact "13_dispatch_driver_login.json" -Detail "driver user_id missing"
        $failFast = $true
      } else {
        Add-Step -Name "dispatch.extract_driver_id" -Ok $true -Status "ok" -DurationMs 0 -TraceId "" -Artifact "13_dispatch_driver_login.json" -Detail "driver_id=$driverId"
      }
    }
  }
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $assign = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/assign" -Body @{ driver_id = $driverId } -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "14_dispatch_assign.json" -Object $assign.payload
  [void](Assert-Status -StepName "dispatch.assign" -Expected @(200) -Actual $assign.status -StartedAt $started -Payload $assign.payload -ArtifactName (Split-Path $artifact -Leaf))
}

$statusSteps = @(
  @{ name = "dispatch.status_enroute_pickup"; value = "enroute_pickup"; file = "15_dispatch_status_enroute_pickup.json" },
  @{ name = "dispatch.status_picked_up"; value = "picked_up"; file = "16_dispatch_status_picked_up.json" },
  @{ name = "dispatch.status_enroute_dropoff"; value = "enroute_dropoff"; file = "17_dispatch_status_enroute_dropoff.json" },
  @{ name = "dispatch.status_delivered"; value = "delivered"; file = "18_dispatch_status_delivered.json" }
)

foreach ($s in $statusSteps) {
  if ($failFast) { break }
  $started = [DateTime]::UtcNow
  $resp = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/status" -Body @{ status = $s.value } -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name $s.file -Object $resp.payload
  [void](Assert-Status -StepName $s.name -Expected @(200) -Actual $resp.status -StartedAt $started -Payload $resp.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not $failFast) {
  $started = [DateTime]::UtcNow
  $trip = Invoke-SmokeRequest -Method "GET" -Path "/dispatch/trips/$tripId" -Body $null -Headers @{ Authorization = "Bearer $AccessToken" }
  $artifact = Save-Artifact -Name "19_dispatch_trip_get.json" -Object $trip.payload
  [void](Assert-Status -StepName "dispatch.trip_get" -Expected @(200) -Actual $trip.status -StartedAt $started -Payload $trip.payload -ArtifactName (Split-Path $artifact -Leaf))
}

if (-not [string]::IsNullOrWhiteSpace($AdminToken)) {
  if (-not $failFast) {
    $started = [DateTime]::UtcNow
    $adminMetrics = Invoke-SmokeRequest -Method "GET" -Path "/admin/metrics?limit=5" -Body $null -Headers @{ "x-admin-token" = $AdminToken }
    $artifact = Save-Artifact -Name "20_admin_metrics.json" -Object $adminMetrics.payload
    [void](Assert-Status -StepName "admin.metrics" -Expected @(200) -Actual $adminMetrics.status -StartedAt $started -Payload $adminMetrics.payload -ArtifactName (Split-Path $artifact -Leaf))
  }
  if (-not $failFast) {
    $started = [DateTime]::UtcNow
    $adminUsers = Invoke-SmokeRequest -Method "GET" -Path "/admin/users?limit=5" -Body $null -Headers @{ "x-admin-token" = $AdminToken }
    $artifact = Save-Artifact -Name "21_admin_users.json" -Object $adminUsers.payload
    [void](Assert-Status -StepName "admin.users" -Expected @(200) -Actual $adminUsers.status -StartedAt $started -Payload $adminUsers.payload -ArtifactName (Split-Path $artifact -Leaf))
  }
  if (-not $failFast) {
    $started = [DateTime]::UtcNow
    $adminTrips = Invoke-SmokeRequest -Method "GET" -Path "/admin/trips?limit=5" -Body $null -Headers @{ "x-admin-token" = $AdminToken }
    $artifact = Save-Artifact -Name "22_admin_trips.json" -Object $adminTrips.payload
    [void](Assert-Status -StepName "admin.trips" -Expected @(200) -Actual $adminTrips.status -StartedAt $started -Payload $adminTrips.payload -ArtifactName (Split-Path $artifact -Leaf))
  }
} else {
  Add-Step -Name "admin.skipped" -Ok $true -Status "skipped" -DurationMs 0 -TraceId "" -Artifact "" -Detail "ADMIN_TOKEN not provided"
}

$ok = -not $failFast
$uniqueTraceIds = @($traceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$totalDurationMs = [int](($steps | Measure-Object -Property duration_ms -Sum).Sum)
$summary = [ordered]@{
  ok = $ok
  base_url = $BaseUrl
  env = $EnvName
  generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  total_duration_ms = $totalDurationMs
  steps = $steps
  failures = $failures
  trace_ids = $uniqueTraceIds
  artifact_dir = $runDir
}
$summaryPath = Join-Path $runDir "summary.json"
($summary | ConvertTo-Json -Depth 40) | Set-Content -Path $summaryPath

if ($ok) {
  Write-Host "PASS: smoke e2e completed"
  Write-Host "summary: $summaryPath"
  exit 0
}

Write-Host "FAIL: smoke e2e encountered failures"
Write-Host "summary: $summaryPath"
exit 1
