param(
  [string]$BaseUrl = "",
  [string]$EnvName = "",
  [string]$SmokeAccessToken = "",
  [string]$SmokePhoneE164 = "",
  [string]$SmokeOtpCode = "",
  [string]$SmokeWebhookSim = "",
  [string]$WebhookSecret = "",
  [string]$PaystackWebhookSecret = "",
  [string]$SmokeDriverId = "",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function To-Bool([object]$Value) {
  if ($null -eq $Value) {
    return $false
  }
  $normalized = "$Value".Trim().ToLowerInvariant()
  return @("1", "true", "yes", "y", "on") -contains $normalized
}

function Try-Get([scriptblock]$Script) {
  try {
    $value = & $Script
    if ($null -eq $value) {
      return ""
    }
    $text = "$value".Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
      return ""
    }
    return $text
  } catch {
    return ""
  }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  if ($env:BASE_URL) {
    $BaseUrl = $env:BASE_URL
  } else {
    $BaseUrl = "https://hail-o-api-staging.onrender.com"
  }
}
if ([string]::IsNullOrWhiteSpace($EnvName)) {
  $EnvName = if ($env:ENV) { $env:ENV } else { "staging" }
}
if ([string]::IsNullOrWhiteSpace($SmokePhoneE164)) {
  if ($env:SMOKE_PHONE_E164) {
    $SmokePhoneE164 = $env:SMOKE_PHONE_E164
  } elseif ($env:TEST_PHONE_E164) {
    $SmokePhoneE164 = $env:TEST_PHONE_E164
  } else {
    $SmokePhoneE164 = $env:E2E_PHONE_E164
  }
}
if ([string]::IsNullOrWhiteSpace($SmokeOtpCode)) {
  if ($env:SMOKE_OTP_CODE) {
    $SmokeOtpCode = $env:SMOKE_OTP_CODE
  } elseif ($env:TEST_OTP) {
    $SmokeOtpCode = $env:TEST_OTP
  } else {
    $SmokeOtpCode = $env:E2E_OTP_CODE
  }
}
if ([string]::IsNullOrWhiteSpace($SmokeWebhookSim)) {
  if ($env:SMOKE_WEBHOOK_SIM) {
    $SmokeWebhookSim = $env:SMOKE_WEBHOOK_SIM
  } elseif ($env:PAYMENTS_TEST_MODE) {
    $SmokeWebhookSim = $env:PAYMENTS_TEST_MODE
  } else {
    $SmokeWebhookSim = ""
  }
}
if ([string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  if ($env:SMOKE_ACCESS_TOKEN) {
    $SmokeAccessToken = $env:SMOKE_ACCESS_TOKEN
  } elseif ($env:TEST_ACCESS_TOKEN) {
    $SmokeAccessToken = $env:TEST_ACCESS_TOKEN
  } else {
    $SmokeAccessToken = $env:E2E_ACCESS_TOKEN
  }
}
if ([string]::IsNullOrWhiteSpace($WebhookSecret)) {
  if ($env:PAYMENTS_WEBHOOK_SECRET) {
    $WebhookSecret = $env:PAYMENTS_WEBHOOK_SECRET
  } else {
    $WebhookSecret = $env:E2E_WEBHOOK_SECRET
  }
}
if ([string]::IsNullOrWhiteSpace($PaystackWebhookSecret)) {
  if ($env:PAYSTACK_WEBHOOK_SECRET) {
    $PaystackWebhookSecret = $env:PAYSTACK_WEBHOOK_SECRET
  } elseif ($env:E2E_PAYSTACK_SECRET) {
    $PaystackWebhookSecret = $env:E2E_PAYSTACK_SECRET
  }
}
if ([string]::IsNullOrWhiteSpace($SmokeDriverId)) {
  if ($env:SMOKE_DRIVER_ID) {
    $SmokeDriverId = $env:SMOKE_DRIVER_ID
  } else {
    $SmokeDriverId = $env:TEST_DRIVER_ID
  }
}

$BaseUrl = $BaseUrl.TrimEnd('/')
$normalizedEnv = $EnvName.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($SmokeWebhookSim)) {
  if (@("staging", "stage", "development", "dev", "test") -contains $normalizedEnv) {
    $SmokeWebhookSim = "true"
  } else {
    $SmokeWebhookSim = "false"
  }
}
$smokeWebhookSimBool = To-Bool $SmokeWebhookSim
if ($DryRun -and [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $SmokeAccessToken = "dry_access_token"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$artifactRoot = Join-Path $scriptDir "test_artifacts/e2e"
$runStamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$runDir = Join-Path $artifactRoot $runStamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$steps = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[object]
$allTraceIds = New-Object System.Collections.Generic.List[string]
$overallOk = $true

function New-TraceId {
  return "smoke-" + [guid]::NewGuid().ToString("N")
}

function Get-DryRunResponse {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body
  )

  switch -Wildcard ($Path) {
    "/health" { return @{ status = 200; payload = @{ ok = $true; service = "hail-o-backend" } } }
    "/ready" { return @{ status = 200; payload = @{ ok = $true; ready = $true; redis_ready = $false; redis_configured = $false } } }
    "/api/ready" { return @{ status = 200; payload = @{ ok = $true; ready = $true; redis_ready = $false; redis_configured = $false } } }
    "/auth/otp/request" { return @{ status = 200; payload = @{ ok = $true } } }
    "/auth/otp/verify" { return @{ status = 200; payload = @{ access_token = "dry_access_token"; refresh_token = "dry_refresh_token"; user = @{ id = "dry-user"; phone_e164 = "+15550001111" } } } }
    "/auth/register" { return @{ status = 201; payload = @{ ok = $true; user_id = "00000000-0000-4000-8000-000000000111" } } }
    "/auth/login" { return @{ status = 200; payload = @{ ok = $true; token = "dry_driver_token"; user_id = "00000000-0000-4000-8000-000000000111" } } }
    "/marketplace/offers*" { return @{ status = 200; payload = @{ ok = $true; data = @(@{ id = "offer_dry_001"; title = "Dry Offer" }) } } }
    "/marketplace/purchases" { return @{ status = 200; payload = @{ ok = $true; data = @{ purchase = @{ purchase_id = "11111111-1111-4111-8111-111111111111"; status = "pending_payment" } } } } }
    "/payments/intents" { return @{ status = 200; payload = @{ ok = $true; data = @{ id = "22222222-2222-4222-8222-222222222222"; status = "pending" } } } }
    "/webhooks/payments" { return @{ status = 200; payload = @{ ok = $true; data = @{ action = "processed" } } } }
    "/marketplace/purchases/*" { return @{ status = 200; payload = @{ ok = $true; data = @{ status = "paid"; purchase = @{ status = "paid" } } } } }
    "/dispatch/quote" { return @{ status = 200; payload = @{ ok = $true; distance_km = 12.3; duration_min_est = 29; price_minor = 4500; currency = "NGN"; breakdown = @{ base_fare_minor = 1000 } } } }
    "/dispatch/trips" { return @{ status = 201; payload = @{ ok = $true; trip = @{ id = "33333333-3333-4333-8333-333333333333"; status = "created" } } } }
    "/dispatch/trips/*/assign" { return @{ status = 200; payload = @{ ok = $true; trip = @{ id = "33333333-3333-4333-8333-333333333333"; status = "assigned" }; assignment = @{ driver_id = "00000000-0000-4000-8000-000000000111"; status = "assigned" } } } }
    "/dispatch/trips/*/status" {
      $statusValue = Try-Get { $Body.status }
      if ([string]::IsNullOrWhiteSpace($statusValue)) { $statusValue = "searching" }
      return @{ status = 200; payload = @{ ok = $true; trip = @{ id = "33333333-3333-4333-8333-333333333333"; status = $statusValue }; event = @{ to_status = $statusValue } } }
    }
    "/dispatch/trips/*" { return @{ status = 200; payload = @{ ok = $true; trip = @{ id = "33333333-3333-4333-8333-333333333333"; status = "delivered" } } } }
    "/admin/metrics" { return @{ status = 200; payload = @{ ok = $true; users_total = 1; trips_total = 1; purchases_total = 1 } } }
    "/admin/users*" { return @{ status = 200; payload = @{ ok = $true; users = @() } } }
    "/admin/trips*" { return @{ status = 200; payload = @{ ok = $true; trips = @() } } }
    "/admin/audit*" { return @{ status = 200; payload = @{ ok = $true; data = @() } } }
    "/admin/smoke/mint_token" { return @{ status = 200; payload = @{ ok = $true; access_token = "dry_access_token"; user = @{ id = "00000000-0000-4000-8000-000000000123"; phone_e164 = "+15550001111" } } } }
    default { return @{ status = 404; payload = @{ ok = $false; error_code = "ROUTE_NOT_FOUND" } } }
  }
}

function Invoke-SmokeRequest {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body,
    [hashtable]$Headers
  )

  $uri = [Uri]::new($BaseUrl + $Path)
  $traceId = New-TraceId
  $requestHeaders = @{
    Accept = "application/json"
    "x-trace-id" = $traceId
  }
  foreach ($kv in $Headers.GetEnumerator()) {
    $requestHeaders[$kv.Key] = $kv.Value
  }

  $startAt = [DateTime]::UtcNow

  if ($DryRun) {
    $stub = Get-DryRunResponse -Method $Method -Path $Path -Body $Body
    $duration = [int]([DateTime]::UtcNow - $startAt).TotalMilliseconds
    return [ordered]@{
      method = $Method
      path = $Path
      url = "$uri"
      status = [int]$stub.status
      duration_ms = $duration
      trace_id = $traceId
      response = $stub.payload
      curl_error = $null
    }
  }

  $statusCode = 0
  $content = ""
  $curlError = $null
  try {
    if ($null -ne $Body) {
      $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
      $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $requestHeaders -ContentType "application/json" -Body $jsonBody
    } else {
      $response = Invoke-WebRequest -UseBasicParsing -Method $Method -Uri $uri -Headers $requestHeaders
    }
    $statusCode = [int]$response.StatusCode
    $content = "$($response.Content)"
  } catch {
    $webResponse = $_.Exception.Response
    if ($null -eq $webResponse) {
      $statusCode = 0
      $curlError = "$($_.Exception.Message)"
    } else {
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
  }

  $payload = $null
  if (-not [string]::IsNullOrWhiteSpace($content)) {
    try {
      $payload = $content | ConvertFrom-Json -Depth 50
    } catch {
      $payload = $content
    }
  }
  if ($null -eq $payload) {
    $payload = [ordered]@{}
  }

  $responseTrace = Try-Get { $payload.trace_id }
  if (-not [string]::IsNullOrWhiteSpace($responseTrace)) {
    $traceId = $responseTrace
  }

  $durationMs = [int]([DateTime]::UtcNow - $startAt).TotalMilliseconds
  return [ordered]@{
    method = $Method
    path = $Path
    url = "$uri"
    status = $statusCode
    duration_ms = $durationMs
    trace_id = $traceId
    response = $payload
    curl_error = $curlError
  }
}

function Redact-Secret([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ""
  }
  $trimmed = $Value.Trim()
  if ($trimmed.Length -le 6) {
    return "$trimmed…"
  }
  return "$($trimmed.Substring(0, 6))…"
}

function Is-SensitiveKey([string]$Key) {
  if ([string]::IsNullOrWhiteSpace($Key)) {
    return $false
  }
  $normalized = $Key.Trim().ToLowerInvariant()
  return $normalized.Contains("token") -or
    $normalized.Contains("secret") -or
    $normalized.Contains("authorization") -or
    $normalized.Contains("password") -or
    $normalized.Contains("signature")
}

function Sanitize-Payload($Value, [string]$ParentKey = "") {
  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $clean = [ordered]@{}
    foreach ($key in $Value.Keys) {
      $keyText = "$key"
      $clean[$keyText] = Sanitize-Payload -Value $Value[$key] -ParentKey $keyText
    }
    return $clean
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $items = @()
    foreach ($item in $Value) {
      $items += ,(Sanitize-Payload -Value $item -ParentKey $ParentKey)
    }
    return $items
  }
  if ($Value -is [string] -and (Is-SensitiveKey $ParentKey)) {
    return Redact-Secret $Value
  }
  return $Value
}

function Save-Step {
  param(
    [string]$StepId,
    [string]$ArtifactFile,
    [bool]$Ok,
    [string]$Status,
    [string]$Note,
    [int]$DurationMs,
    [string[]]$TraceIds,
    [object]$Payload
  )

  $artifactPayload = [ordered]@{
    step = $StepId
    ok = $Ok
    status = $Status
    note = $Note
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    payload = (Sanitize-Payload -Value $Payload)
  }
  $artifactPath = Join-Path $runDir $ArtifactFile
  ($artifactPayload | ConvertTo-Json -Depth 80) | Set-Content -Path $artifactPath

  $entry = [ordered]@{
    step = $StepId
    ok = $Ok
    status = $Status
    note = $Note
    duration_ms = $DurationMs
    trace_ids = @($TraceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    artifact = $ArtifactFile
  }
  $steps.Add($entry)
  foreach ($trace in $entry.trace_ids) {
    if (-not [string]::IsNullOrWhiteSpace($trace)) {
      $allTraceIds.Add($trace)
    }
  }
  if (-not $Ok) {
    $script:overallOk = $false
    $failures.Add([ordered]@{
      step = $StepId
      status = $Status
      note = $Note
      artifact = $ArtifactFile
    })
  }
}

function Sum-DurationMs([System.Collections.IEnumerable]$Items) {
  $sum = 0
  foreach ($item in $Items) {
    $value = 0
    if ($item -is [System.Collections.IDictionary]) {
      $value = $item['duration_ms']
    } elseif ($null -ne $item -and $null -ne $item.PSObject.Properties['duration_ms']) {
      $value = $item.duration_ms
    }
    if ($null -ne $value -and "$value" -match '^-?\d+$') {
      $sum += [int]$value
    }
  }
  return $sum
}

Write-Host "[smoke] base=$BaseUrl env=$normalizedEnv dry_run=$DryRun"
Write-Host "[smoke] artifacts=$runDir"
# Step 01: Health
$step01 = Invoke-SmokeRequest -Method "GET" -Path "/health" -Body $null -Headers @{}
$step01Ok = ($step01.status -eq 200) -and (To-Bool (Try-Get { $step01.response.ok }))
$step01Note = if ($step01Ok) { "Health responded with ok=true" } else { "Expected HTTP 200 and ok=true" }
Save-Step -StepId "01_health" -ArtifactFile "01_health.json" -Ok $step01Ok -Status "$($step01.status)" -Note $step01Note -DurationMs ([int]$step01.duration_ms) -TraceIds @($step01.trace_id) -Payload ([ordered]@{ call = $step01; expected = "status=200 and ok=true" })

# Step 02: Ready
$step02 = Invoke-SmokeRequest -Method "GET" -Path "/ready" -Body $null -Headers @{}
if ($step02.status -eq 404) {
  $step02 = Invoke-SmokeRequest -Method "GET" -Path "/api/ready" -Body $null -Headers @{}
}
$step02Ok = ($step02.status -eq 200) -and (To-Bool (Try-Get { $step02.response.ok }))
$step02Note = if ($step02Ok) { "Ready responded with ok=true" } else { "Expected HTTP 200 and ok=true" }
Save-Step -StepId "02_ready" -ArtifactFile "02_ready.json" -Ok $step02Ok -Status "$($step02.status)" -Note $step02Note -DurationMs ([int]$step02.duration_ms) -TraceIds @($step02.trace_id) -Payload ([ordered]@{ call = $step02; expected = "status=200 and ok=true" })

# Step 03: Auth
$authOps = New-Object System.Collections.Generic.List[object]
$authMode = "none"
$authNote = ""
$needsUserInput = $false

if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $authMode = "access_token"
  $authNote = "Using SMOKE_ACCESS_TOKEN"
} else {
  $authMode = "otp"
  if ([string]::IsNullOrWhiteSpace($SmokePhoneE164)) {
    $authNote = "SMOKE_PHONE_E164 is required when SMOKE_ACCESS_TOKEN is not set"
  } else {
    $otpRequest = Invoke-SmokeRequest -Method "POST" -Path "/auth/otp/request" -Body @{ phone_e164 = $SmokePhoneE164 } -Headers @{}
    $authOps.Add($otpRequest)
    if ([string]::IsNullOrWhiteSpace($SmokeOtpCode)) {
      $needsUserInput = $true
      $authNote = "OTP requested. Re-run with SMOKE_OTP_CODE=XXXXXX"
    } else {
      $otpVerify = Invoke-SmokeRequest -Method "POST" -Path "/auth/otp/verify" -Body @{ phone_e164 = $SmokePhoneE164; code = $SmokeOtpCode } -Headers @{}
      $authOps.Add($otpVerify)
      $SmokeAccessToken = Try-Get { $otpVerify.response.access_token }
      if ([string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
        $SmokeAccessToken = Try-Get { $otpVerify.response.data.access_token }
      }
      if ([string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
        $SmokeAccessToken = Try-Get { $otpVerify.response.token }
      }
      if ([string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
        $authNote = "OTP verify did not return access token"
      } else {
        $authNote = "OTP flow verified and access token acquired"
      }
    }
  }
}

$step03Ok = -not [string]::IsNullOrWhiteSpace($SmokeAccessToken)
$step03Status = if ($needsUserInput) { "needs_input" } elseif ($step03Ok) { "ok" } else { "auth_failed" }
$step03Artifact = if ($needsUserInput) { "03_auth_need_input.json" } else { "03_auth.json" }
if ([string]::IsNullOrWhiteSpace($authNote)) {
  $authNote = "Authentication flow completed"
}
$step03Duration = Sum-DurationMs $authOps
$step03TraceIds = @($authOps | ForEach-Object { $_.trace_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
Save-Step -StepId "03_auth" -ArtifactFile $step03Artifact -Ok $step03Ok -Status $step03Status -Note $authNote -DurationMs $step03Duration -TraceIds $step03TraceIds -Payload ([ordered]@{ auth_mode = $authMode; token_acquired = $step03Ok; needs_input = $needsUserInput; access_token_preview = (Redact-Secret $SmokeAccessToken); note = $authNote; operations = $authOps })

if ($needsUserInput) {
  $summaryNeedsInput = [ordered]@{
    ok = $false
    base_url = $BaseUrl
    env = $normalizedEnv
    generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    total_duration_ms = Sum-DurationMs $steps
    steps = $steps
    failures = $failures
    trace_ids = @($allTraceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    artifact_dir = $runDir
  }
  $summaryNeedsInputPath = Join-Path $runDir "summary.json"
  ($summaryNeedsInput | ConvertTo-Json -Depth 80) | Set-Content -Path $summaryNeedsInputPath
  Write-Host "OTP requested. Re-run with SMOKE_OTP_CODE=XXXXXX"
  Write-Host "summary: $summaryNeedsInputPath"
  exit 2
}

$offerId = ""
$purchaseId = ""
$intentId = ""
$tripId = ""

# Step 04: Offers
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $step04 = Invoke-SmokeRequest -Method "GET" -Path "/marketplace/offers?limit=5" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
  $offerId = Try-Get { $step04.response.data[0].id }
  if ([string]::IsNullOrWhiteSpace($offerId)) {
    $offerId = Try-Get { $step04.response.offers[0].id }
  }
  if ([string]::IsNullOrWhiteSpace($offerId)) {
    $offerId = Try-Get { $step04.response.data.offers[0].id }
  }
  $step04Ok = ($step04.status -eq 200) -and (-not [string]::IsNullOrWhiteSpace($offerId))
  $step04Note = if ($step04Ok) { "Selected offer_id=$offerId" } else { "Expected HTTP 200 and at least one offer id" }
  Save-Step -StepId "04_offers" -ArtifactFile "04_offers.json" -Ok $step04Ok -Status "$($step04.status)" -Note $step04Note -DurationMs ([int]$step04.duration_ms) -TraceIds @($step04.trace_id) -Payload ([ordered]@{ offer_id = $offerId; call = $step04 })
} else {
  Save-Step -StepId "04_offers" -ArtifactFile "04_offers.json" -Ok $false -Status "missing_auth" -Note "Access token unavailable" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_access_token" })
}

# Step 05: Purchase create
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken) -and -not [string]::IsNullOrWhiteSpace($offerId)) {
  $purchaseIdempotency = "smoke-purchase-" + [guid]::NewGuid().ToString("N")
  $step05 = Invoke-SmokeRequest -Method "POST" -Path "/marketplace/purchases" -Body @{ offer_id = $offerId; quantity = 1 } -Headers @{ Authorization = "Bearer $SmokeAccessToken"; "idempotency-key" = $purchaseIdempotency }
  $purchaseId = Try-Get { $step05.response.data.purchase_id }
  if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = Try-Get { $step05.response.data.purchase.purchase_id } }
  if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = Try-Get { $step05.response.data.purchase.id } }
  if ([string]::IsNullOrWhiteSpace($purchaseId)) { $purchaseId = Try-Get { $step05.response.purchase_id } }
  $step05Ok = (($step05.status -eq 200) -or ($step05.status -eq 201)) -and (-not [string]::IsNullOrWhiteSpace($purchaseId))
  $step05Note = if ($step05Ok) { "Created purchase_id=$purchaseId" } else { "Expected HTTP 200/201 and purchase_id" }
  Save-Step -StepId "05_purchase_create" -ArtifactFile "05_purchase_create.json" -Ok $step05Ok -Status "$($step05.status)" -Note $step05Note -DurationMs ([int]$step05.duration_ms) -TraceIds @($step05.trace_id) -Payload ([ordered]@{ purchase_id = $purchaseId; call = $step05 })
} else {
  Save-Step -StepId "05_purchase_create" -ArtifactFile "05_purchase_create.json" -Ok $false -Status "prerequisite_missing" -Note "Requires access token and offer id" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_prerequisites" })
}

# Step 06: Intent create
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken) -and -not [string]::IsNullOrWhiteSpace($purchaseId)) {
  $intentIdempotency = "smoke-intent-" + [guid]::NewGuid().ToString("N")
  $step06 = Invoke-SmokeRequest -Method "POST" -Path "/payments/intents" -Body @{ purchase_id = $purchaseId } -Headers @{ Authorization = "Bearer $SmokeAccessToken"; "idempotency-key" = $intentIdempotency }
  $intentId = Try-Get { $step06.response.data.id }
  if ([string]::IsNullOrWhiteSpace($intentId)) { $intentId = Try-Get { $step06.response.id } }
  $step06Ok = ($step06.status -eq 200) -and (-not [string]::IsNullOrWhiteSpace($intentId))
  $step06Note = if ($step06Ok) { "Created intent_id=$intentId" } else { "Expected HTTP 200 and intent id" }
  Save-Step -StepId "06_intent_create" -ArtifactFile "06_intent_create.json" -Ok $step06Ok -Status "$($step06.status)" -Note $step06Note -DurationMs ([int]$step06.duration_ms) -TraceIds @($step06.trace_id) -Payload ([ordered]@{ intent_id = $intentId; call = $step06 })
} else {
  Save-Step -StepId "06_intent_create" -ArtifactFile "06_intent_create.json" -Ok $false -Status "prerequisite_missing" -Note "Requires access token and purchase id" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_prerequisites" })
}
# Step 07: Webhook simulation (staging only test mode)
$allowWebhookSim = $smokeWebhookSimBool -and ($normalizedEnv -ne "prod") -and ($normalizedEnv -ne "production") -and (-not [string]::IsNullOrWhiteSpace($purchaseId))
$runWebhookSim = $false
$allowPendingPurchase = $false
$step07SkipReason = ""

if ($allowWebhookSim) {
  if ([string]::IsNullOrWhiteSpace($PaystackWebhookSecret)) {
    $step07SkipReason = "Webhook simulation skipped: PAYSTACK_WEBHOOK_SECRET not provided to ops runtime"
  } else {
    $runWebhookSim = $true
  }
} elseif (-not $smokeWebhookSimBool) {
  $step07SkipReason = "Webhook simulation disabled by SMOKE_WEBHOOK_SIM=false"
} elseif ($normalizedEnv -eq "prod" -or $normalizedEnv -eq "production") {
  $step07SkipReason = "Webhook simulation disabled in production environment"
} else {
  $step07SkipReason = "Webhook simulation skipped because purchase_id is unavailable"
}

if ($runWebhookSim) {
  $providerEventId = "evt-smoke-" + [guid]::NewGuid().ToString("N")
  $webhookPayload = [ordered]@{
    provider_event_id = $providerEventId
    event_id = $providerEventId
    event_type = "payment_succeeded"
    purchase_id = $purchaseId
    event = "charge.success"
    data = [ordered]@{
      id = $providerEventId
      metadata = [ordered]@{ purchase_id = $purchaseId }
    }
  }
  $payloadJson = $webhookPayload | ConvertTo-Json -Depth 20 -Compress
  $headers = @{}

  if (-not [string]::IsNullOrWhiteSpace($WebhookSecret)) {
    $hmac256 = New-Object System.Security.Cryptography.HMACSHA256
    $hmac256.Key = [Text.Encoding]::UTF8.GetBytes($WebhookSecret)
    $sigBytes = $hmac256.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadJson))
    $sig = -join ($sigBytes | ForEach-Object { $_.ToString("x2") })
    $headers["x-webhook-signature"] = $sig
  }

  $hmac512 = New-Object System.Security.Cryptography.HMACSHA512
  $hmac512.Key = [Text.Encoding]::UTF8.GetBytes($PaystackWebhookSecret)
  $sigBytes = $hmac512.ComputeHash([Text.Encoding]::UTF8.GetBytes($payloadJson))
  $sig = -join ($sigBytes | ForEach-Object { $_.ToString("x2") })
  $headers["x-paystack-signature"] = $sig
  $headers["x-paystack-event-id"] = $providerEventId

  $step07 = Invoke-SmokeRequest -Method "POST" -Path "/webhooks/payments" -Body $webhookPayload -Headers $headers
  $step07Status = "$($step07.status)"
  $step07Ok = $false
  $step07Note = "Expected HTTP 200/202 from webhook simulation"
  if ($step07.status -eq 200 -or $step07.status -eq 202) {
    $step07Ok = $true
    $step07Note = "Webhook simulation accepted"
  } elseif ($step07.status -eq 404 -or $step07.status -eq 405) {
    $step07Ok = $true
    $step07Status = "skipped"
    $allowPendingPurchase = $true
    $step07SkipReason = "Webhook simulation endpoint unavailable on target"
    $step07Note = $step07SkipReason
  }
  Save-Step -StepId "07_webhook_sim" -ArtifactFile "07_webhook_sim.json" -Ok $step07Ok -Status $step07Status -Note $step07Note -DurationMs ([int]$step07.duration_ms) -TraceIds @($step07.trace_id) -Payload ([ordered]@{ provider_event_id = $providerEventId; skipped_reason = $step07SkipReason; call = $step07 })
} else {
  $allowPendingPurchase = $true
  Save-Step -StepId "07_webhook_sim" -ArtifactFile "07_webhook_sim.json" -Ok $true -Status "skipped" -Note $step07SkipReason -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ skipped = $true; skipped_reason = $step07SkipReason })
}

# Step 08: Purchase polling up to 45s
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken) -and -not [string]::IsNullOrWhiteSpace($purchaseId)) {
  $pollOps = New-Object System.Collections.Generic.List[object]
  $pollStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $deadlineAt = [DateTime]::UtcNow.AddSeconds(45)
  $finalStatus = ""
  $terminalOutcome = "timeout"

  while ($true) {
    $pollCall = Invoke-SmokeRequest -Method "GET" -Path "/marketplace/purchases/$purchaseId" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $pollOps.Add($pollCall)
    $pollHttpStatus = [int]$pollCall.status
    $finalStatus = Try-Get { $pollCall.response.data.status }
    if ([string]::IsNullOrWhiteSpace($finalStatus)) { $finalStatus = Try-Get { $pollCall.response.data.purchase.status } }
    if ([string]::IsNullOrWhiteSpace($finalStatus)) { $finalStatus = Try-Get { $pollCall.response.status } }
    $finalStatus = $finalStatus.ToLowerInvariant()

    if ($pollHttpStatus -ne 200) {
      $terminalOutcome = "http_error"
      break
    }
    if ($finalStatus -eq "paid" -or $finalStatus -eq "active") {
      $terminalOutcome = "paid"
      break
    }
    if ($allowPendingPurchase -and ($finalStatus -eq "pending_payment" -or $finalStatus -eq "pending")) {
      $terminalOutcome = "pending"
      break
    }
    if ($finalStatus -eq "failed" -or $finalStatus -eq "canceled" -or $finalStatus -eq "cancelled") {
      $terminalOutcome = "failed"
      break
    }
    if ([DateTime]::UtcNow -ge $deadlineAt) {
      $terminalOutcome = "timeout"
      break
    }
    Start-Sleep -Seconds 3
  }

  $pollStopwatch.Stop()
  $step08Ok = ($terminalOutcome -eq "paid") -or ($allowPendingPurchase -and ($terminalOutcome -eq "pending"))
  $step08Status = if ($step08Ok) { "ok" } else { $terminalOutcome }
  $step08Note = if ($step08Ok) {
    if ($terminalOutcome -eq "paid") {
      "Purchase reached terminal paid state ($finalStatus)"
    } else {
      "Purchase remained pending as expected when webhook simulation is skipped ($finalStatus)"
    }
  } else {
    "Purchase status=$finalStatus"
  }
  $step08TraceIds = @($pollOps | ForEach-Object { $_.trace_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  Save-Step -StepId "08_purchase_poll" -ArtifactFile "08_purchase_poll.json" -Ok $step08Ok -Status $step08Status -Note $step08Note -DurationMs ([int]$pollStopwatch.ElapsedMilliseconds) -TraceIds $step08TraceIds -Payload ([ordered]@{ purchase_id = $purchaseId; final_status = $finalStatus; terminal_outcome = $terminalOutcome; attempts = $pollOps })
} else {
  Save-Step -StepId "08_purchase_poll" -ArtifactFile "08_purchase_poll.json" -Ok $false -Status "prerequisite_missing" -Note "Requires access token and purchase id" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_prerequisites" })
}

# Step 09: Dispatch quote
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $step09 = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/quote" -Body @{ pickup = @{ lat = 6.455; lng = 3.384 }; dropoff = @{ lat = 6.6018; lng = 3.3515 }; service_level = "standard" } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
  $hasFields = ($null -ne $step09.response.distance_km) -and ($null -ne $step09.response.duration_min_est) -and ($null -ne $step09.response.price_minor) -and (-not [string]::IsNullOrWhiteSpace((Try-Get { $step09.response.currency })))
  $step09Ok = ($step09.status -eq 200) -and $hasFields
  $step09Note = if ($step09Ok) { "Quote validated (price_minor=$($step09.response.price_minor), distance_km=$($step09.response.distance_km))" } else { "Expected HTTP 200 with distance_km, duration_min_est, price_minor, currency" }
  Save-Step -StepId "09_quote" -ArtifactFile "09_quote.json" -Ok $step09Ok -Status "$($step09.status)" -Note $step09Note -DurationMs ([int]$step09.duration_ms) -TraceIds @($step09.trace_id) -Payload ([ordered]@{ call = $step09 })
} else {
  Save-Step -StepId "09_quote" -ArtifactFile "09_quote.json" -Ok $false -Status "missing_auth" -Note "Access token unavailable" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_access_token" })
}

# Step 10: Trip create
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $step10 = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips" -Body @{ pickup = @{ lat = 6.455; lng = 3.384; address = "Lagos Island" }; dropoff = @{ lat = 6.6018; lng = 3.3515; address = "Ikeja" }; notes = "smoke run" } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
  $tripId = Try-Get { $step10.response.trip.id }
  if ([string]::IsNullOrWhiteSpace($tripId)) {
    $tripId = Try-Get { $step10.response.data.trip.id }
  }
  $step10Ok = (($step10.status -eq 200) -or ($step10.status -eq 201)) -and (-not [string]::IsNullOrWhiteSpace($tripId))
  $step10Note = if ($step10Ok) { "Created trip_id=$tripId" } else { "Expected HTTP 200/201 and trip id" }
  Save-Step -StepId "10_trip_create" -ArtifactFile "10_trip_create.json" -Ok $step10Ok -Status "$($step10.status)" -Note $step10Note -DurationMs ([int]$step10.duration_ms) -TraceIds @($step10.trace_id) -Payload ([ordered]@{ trip_id = $tripId; call = $step10 })
} else {
  Save-Step -StepId "10_trip_create" -ArtifactFile "10_trip_create.json" -Ok $false -Status "missing_auth" -Note "Access token unavailable" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_access_token" })
}

# Step 11: Trip status lifecycle + assignment
if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken) -and -not [string]::IsNullOrWhiteSpace($tripId)) {
  $step11Ops = New-Object System.Collections.Generic.List[object]
  $step11Watch = [System.Diagnostics.Stopwatch]::StartNew()
  $step11FlowOk = $true
  $step11Note = "Trip reached delivered state"
  $assignSupported = "unknown"

  $searchingCall = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/status" -Body @{ status = "searching" } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
  $step11Ops.Add($searchingCall)
  if ($searchingCall.status -ne 200) {
    $step11FlowOk = $false
    $step11Note = "Failed to transition trip to searching"
  }

  $driverId = $SmokeDriverId
  if ($step11FlowOk -and [string]::IsNullOrWhiteSpace($driverId)) {
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $driverEmail = "smoke.driver.$stamp@hailo.dev"
    $driverPass = "Passw0rd!"
    $driverRegister = Invoke-SmokeRequest -Method "POST" -Path "/auth/register" -Body @{ email = $driverEmail; password = $driverPass; role = "driver"; display_name = "Smoke Driver" } -Headers @{ "idempotency-key" = "smoke-driver-$stamp" }
    $step11Ops.Add($driverRegister)
    if ($driverRegister.status -ne 201) {
      $step11FlowOk = $false
      $step11Note = "Failed to create smoke driver account"
    } else {
      $driverId = Try-Get { $driverRegister.response.user_id }
      if ([string]::IsNullOrWhiteSpace($driverId)) {
        $driverId = Try-Get { $driverRegister.response.data.user_id }
      }
      if ([string]::IsNullOrWhiteSpace($driverId)) {
        $step11FlowOk = $false
        $step11Note = "Driver creation succeeded but user_id was missing"
      }
    }
  }

  if ($step11FlowOk) {
    $assignCall = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/assign" -Body @{ driver_id = $driverId } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $step11Ops.Add($assignCall)
    if ($assignCall.status -eq 200) {
      $assignSupported = "true"
    } elseif ($assignCall.status -eq 404 -or $assignCall.status -eq 405) {
      $assignSupported = "false"
      $assignedFallback = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/status" -Body @{ status = "assigned" } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
      $step11Ops.Add($assignedFallback)
      if ($assignedFallback.status -ne 200) {
        $step11FlowOk = $false
        $step11Note = "Assign endpoint unavailable and fallback status transition failed"
      }
    } else {
      $step11FlowOk = $false
      $step11Note = "Assign call failed unexpectedly"
    }
  }

  foreach ($transition in @("enroute_pickup", "picked_up", "enroute_dropoff", "delivered")) {
    if (-not $step11FlowOk) {
      break
    }
    $transitionCall = Invoke-SmokeRequest -Method "POST" -Path "/dispatch/trips/$tripId/status" -Body @{ status = $transition } -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $step11Ops.Add($transitionCall)
    if ($transitionCall.status -ne 200) {
      $step11FlowOk = $false
      $step11Note = "Failed transition to $transition"
      break
    }
  }

  if ($step11FlowOk) {
    $tripGetCall = Invoke-SmokeRequest -Method "GET" -Path "/dispatch/trips/$tripId" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $step11Ops.Add($tripGetCall)
    if ($tripGetCall.status -ne 200) {
      $step11FlowOk = $false
      $step11Note = "Failed to fetch trip after transitions"
    } else {
      $finalTripStatus = Try-Get { $tripGetCall.response.trip.status }
      if ([string]::IsNullOrWhiteSpace($finalTripStatus)) {
        $finalTripStatus = Try-Get { $tripGetCall.response.data.trip.status }
      }
      $finalTripStatus = $finalTripStatus.ToLowerInvariant()
      if ($finalTripStatus -ne "delivered") {
        $step11FlowOk = $false
        $step11Note = "Trip final status is $finalTripStatus, expected delivered"
      }
    }
  }

  $step11Watch.Stop()
  $step11TraceIds = @($step11Ops | ForEach-Object { $_.trace_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  $step11Status = if ($step11FlowOk) { "ok" } else { "trip_flow_failed" }
  Save-Step -StepId "11_trip_status_flow" -ArtifactFile "11_trip_status_flow.json" -Ok $step11FlowOk -Status $step11Status -Note $step11Note -DurationMs ([int]$step11Watch.ElapsedMilliseconds) -TraceIds $step11TraceIds -Payload ([ordered]@{ trip_id = $tripId; assign_supported = $assignSupported; note = $step11Note; operations = $step11Ops })
} else {
  Save-Step -StepId "11_trip_status_flow" -ArtifactFile "11_trip_status_flow.json" -Ok $false -Status "prerequisite_missing" -Note "Requires access token and trip id" -DurationMs 0 -TraceIds @() -Payload ([ordered]@{ error = "missing_prerequisites" })
}
# Step 12: Admin metrics/users/trips
$adminOps = New-Object System.Collections.Generic.List[object]
$adminStatus = "skipped"
$adminOk = $true
$adminNote = "Admin flow skipped (no admin access available)"

if (-not [string]::IsNullOrWhiteSpace($SmokeAccessToken)) {
  $bearerMetrics = Invoke-SmokeRequest -Method "GET" -Path "/admin/metrics" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
  $adminOps.Add($bearerMetrics)
  if ($bearerMetrics.status -eq 200) {
    $bearerUsers = Invoke-SmokeRequest -Method "GET" -Path "/admin/users?limit=5" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $bearerTrips = Invoke-SmokeRequest -Method "GET" -Path "/admin/trips?limit=5" -Body $null -Headers @{ Authorization = "Bearer $SmokeAccessToken" }
    $adminOps.Add($bearerUsers)
    $adminOps.Add($bearerTrips)
    if ($bearerUsers.status -eq 200 -and $bearerTrips.status -eq 200) {
      $adminStatus = "ok"
      $adminOk = $true
      $adminNote = "Admin endpoints succeeded via bearer token"
    } else {
      $adminStatus = "admin_flow_failed"
      $adminOk = $false
      $adminNote = "Admin bearer token flow failed for users/trips endpoints"
    }
  } elseif ($bearerMetrics.status -eq 401 -or $bearerMetrics.status -eq 403) {
    $adminStatus = "skipped"
    $adminOk = $true
    $adminNote = "Admin endpoints unavailable for current bearer token (non-admin)"
  } else {
    $adminStatus = "admin_flow_failed"
    $adminOk = $false
    $adminNote = "Admin metrics request failed unexpectedly"
  }
}

$step12Duration = Sum-DurationMs $adminOps
$step12TraceIds = @($adminOps | ForEach-Object { $_.trace_id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
Save-Step -StepId "12_admin_metrics" -ArtifactFile "12_admin_metrics.json" -Ok $adminOk -Status $adminStatus -Note $adminNote -DurationMs $step12Duration -TraceIds $step12TraceIds -Payload ([ordered]@{ note = $adminNote; operations = $adminOps })

$summary = [ordered]@{
  ok = $overallOk
  base_url = $BaseUrl
  env = $normalizedEnv
  generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  total_duration_ms = Sum-DurationMs $steps
  steps = $steps
  failures = $failures
  trace_ids = @($allTraceIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  artifact_dir = $runDir
}
$summaryPath = Join-Path $runDir "summary.json"
($summary | ConvertTo-Json -Depth 80) | Set-Content -Path $summaryPath

if ($overallOk) {
  Write-Host "PASS: smoke e2e completed"
  Write-Host "summary: $summaryPath"
  exit 0
}

Write-Host "FAIL: smoke e2e encountered failures"
Write-Host "summary: $summaryPath"
exit 1
