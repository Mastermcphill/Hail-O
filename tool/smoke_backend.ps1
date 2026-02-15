$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-CurlJson {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][hashtable]$Headers,
    [Parameter(Mandatory = $true)][string]$JsonBody,
    [switch]$IncludeResponseHeaders
  )

  $tmpPath = [System.IO.Path]::GetTempFileName()
  try {
    [System.IO.File]::WriteAllText($tmpPath, $JsonBody, $utf8NoBom)
    $curlArgs = @('-sS')
    if ($IncludeResponseHeaders.IsPresent) {
      $curlArgs += '-i'
    }
    $curlArgs += @(
      '-X', $Method,
      $Url
    )
    foreach ($headerKey in $Headers.Keys) {
      $curlArgs += @('-H', "${headerKey}: $($Headers[$headerKey])")
    }
    $curlArgs += @('--data-binary', "@$tmpPath")
    return (& curl.exe @curlArgs)
  } finally {
    if (Test-Path $tmpPath) {
      Remove-Item $tmpPath -Force
    }
  }
}

$baseUrl = if ($env:HAILO_API_BASE_URL) { $env:HAILO_API_BASE_URL } else { 'https://hail-o-api.onrender.com' }
$email = "smoke.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())@hailo.dev"
$password = if ($env:HAILO_SMOKE_PASSWORD) { $env:HAILO_SMOKE_PASSWORD } else { 'Passw0rd!' }
$registerKey = "smoke-register-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$rideLookupId = "smoke-non-existent-ride"

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
Invoke-CurlJson `
  -Method 'POST' `
  -Url "$baseUrl/auth/register" `
  -Headers @{
    'Content-Type' = 'application/json'
    'Idempotency-Key' = $registerKey
  } `
  -JsonBody $registerBody `
  -IncludeResponseHeaders

$loginBody = @{
  email = $email
  password = $password
} | ConvertTo-Json -Compress

Write-Output "`n=== LOGIN ==="
$loginRaw = Invoke-CurlJson `
  -Method 'POST' `
  -Url "$baseUrl/auth/login" `
  -Headers @{
    'Content-Type' = 'application/json'
  } `
  -JsonBody $loginBody
Write-Output $loginRaw

$login = $loginRaw | ConvertFrom-Json
if (-not $login.token) {
  throw "Missing token in login response"
}

Write-Output "`n=== AUTHENTICATED CALL ==="
curl.exe -sS -i `
  "$baseUrl/rides/$rideLookupId" `
  -H "Authorization: Bearer $($login.token)"
