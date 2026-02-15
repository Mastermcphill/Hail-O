$ErrorActionPreference = 'Stop'

$baseUrl = if ($env:HAILO_API_BASE_URL) { $env:HAILO_API_BASE_URL } else { 'https://hail-o-api.onrender.com' }
$email = "smoke.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())@hailo.dev"
$password = if ($env:HAILO_SMOKE_PASSWORD) { $env:HAILO_SMOKE_PASSWORD } else { 'Passw0rd!' }
$registerKey = "smoke-register-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$rideKey = "smoke-ride-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$scheduledAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

Write-Output "BASE_URL=$baseUrl"
Write-Output "EMAIL=$email"

Write-Output "`n=== HEALTH ==="
curl.exe -sS -i "$baseUrl/health"

$registerBody = @{
  email = $email
  password = $password
  role = 'rider'
  display_name = 'Smoke Rider'
} | ConvertTo-Json -Compress

Write-Output "`n=== REGISTER ==="
curl.exe -sS -i `
  -X POST "$baseUrl/auth/register" `
  -H "Content-Type: application/json" `
  -H "Idempotency-Key: $registerKey" `
  --data-raw "$registerBody"

$loginBody = @{
  email = $email
  password = $password
} | ConvertTo-Json -Compress

Write-Output "`n=== LOGIN ==="
$loginRaw = curl.exe -sS `
  -X POST "$baseUrl/auth/login" `
  -H "Content-Type: application/json" `
  --data-raw "$loginBody"
Write-Output $loginRaw

$login = $loginRaw | ConvertFrom-Json
if (-not $login.token) {
  throw "Missing token in login response"
}

$rideBody = @{
  scheduled_departure_at = $scheduledAt
  trip_scope = 'intra_city'
  distance_meters = 12000
  duration_seconds = 1800
  luggage_count = 1
  vehicle_class = 'sedan'
  base_fare_minor = 100000
  premium_markup_minor = 5000
  connection_fee_minor = 5000
} | ConvertTo-Json -Compress

Write-Output "`n=== REQUEST RIDE ==="
curl.exe -sS -i `
  -X POST "$baseUrl/rides/request" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $($login.token)" `
  -H "Idempotency-Key: $rideKey" `
  --data-raw "$rideBody"
