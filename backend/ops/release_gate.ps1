param(
  [string]$EnvName = "",
  [string]$BaseUrl = "",
  [string]$StagingBaseUrl = "",
  [string]$RequiredMigrationHead = "",
  [switch]$RequireParity
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($EnvName)) {
  $EnvName = if ($env:ENV) { $env:ENV } else { "staging" }
}
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  $BaseUrl = $env:BASE_URL
}
if ([string]::IsNullOrWhiteSpace($StagingBaseUrl)) {
  $StagingBaseUrl = $env:STAGING_BASE_URL
}
if ([string]::IsNullOrWhiteSpace($RequiredMigrationHead)) {
  $RequiredMigrationHead = $env:REQUIRED_MIGRATION_HEAD
}
if (-not $RequireParity.IsPresent) {
  $RequireParity = @("1", "true", "yes", "y", "on") -contains "$($env:RELEASE_GATE_REQUIRE_PARITY)".Trim().ToLowerInvariant()
}

function Fail([string]$Message) {
  Write-Host "RELEASE GATE: FAIL - $Message"
  exit 1
}

function Require-Env([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    Fail("missing required env var: $Name")
  }
}

function To-Bool([object]$Value) {
  if ($null -eq $Value) {
    return $false
  }
  $normalized = "$Value".Trim().ToLowerInvariant()
  return @("1", "true", "yes", "y", "on") -contains $normalized
}

function Get-ReadyPayload([string]$Base) {
  $normalizedBase = $Base.TrimEnd("/")
  $paths = @("/ready", "/api/ready")
  foreach ($path in $paths) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Method GET -Uri "$normalizedBase$path"
      if ($response.StatusCode -eq 200) {
        return [ordered]@{
          status = $response.StatusCode
          payload = ($response.Content | ConvertFrom-Json)
        }
      }
      return [ordered]@{
        status = [int]$response.StatusCode
        payload = $null
      }
    } catch {
      $webResponse = $_.Exception.Response
      if ($null -eq $webResponse) {
        continue
      }
      $statusCode = [int]$webResponse.StatusCode
      if ($statusCode -eq 404) {
        continue
      }
      try {
        $stream = $webResponse.GetResponseStream()
        if ($null -ne $stream) {
          $reader = New-Object System.IO.StreamReader($stream)
          $body = $reader.ReadToEnd()
          $reader.Dispose()
          return [ordered]@{
            status = $statusCode
            payload = $body
          }
        }
      } catch {
        return [ordered]@{
          status = $statusCode
          payload = $null
        }
      }
      return [ordered]@{
        status = $statusCode
        payload = $null
      }
    }
  }
  return [ordered]@{
    status = 404
    payload = $null
  }
}

function Test-Ready([string]$Label, [string]$Base, [string]$RequiredHead) {
  $result = Get-ReadyPayload -Base $Base
  if ($result.status -ne 200) {
    Fail("$Label readiness check failed with status $($result.status)")
  }
  $payload = $result.payload
  if ($null -eq $payload) {
    Fail("$Label readiness response payload is empty")
  }

  $ok = To-Bool $payload.ok
  $ready = if ($null -ne $payload.ready) { To-Bool $payload.ready } else { $ok }
  if (-not $ok -or -not $ready) {
    Fail("$Label readiness payload reports not ready")
  }

  if ($null -ne $payload.migrations_ok -and -not (To-Bool $payload.migrations_ok)) {
    Fail("$Label migrations_ok is false")
  }

  $expectedHead = if ($null -ne $payload.expected_migration_head) { "$($payload.expected_migration_head)" } else { "" }
  $appliedHead = if ($null -ne $payload.applied_migration_head) { "$($payload.applied_migration_head)" } else { "" }
  if (-not [string]::IsNullOrWhiteSpace($expectedHead) -and
      -not [string]::IsNullOrWhiteSpace($appliedHead) -and
      $expectedHead -ne $appliedHead) {
    Fail("$Label migration head mismatch: expected=$expectedHead applied=$appliedHead")
  }
  if (-not [string]::IsNullOrWhiteSpace($RequiredHead) -and
      -not [string]::IsNullOrWhiteSpace($appliedHead) -and
      $RequiredHead -ne $appliedHead) {
    Fail("$Label migration head mismatch against required head=$RequiredHead (applied=$appliedHead)")
  }

  Write-Host "[release-gate] $Label readiness check passed"
}

function Get-Commit([string]$Base) {
  $normalizedBase = $Base.TrimEnd("/")
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Method GET -Uri "$normalizedBase/version"
    if ($response.StatusCode -ne 200) {
      return ""
    }
    $payload = $response.Content | ConvertFrom-Json
    if ($null -ne $payload.commit -and -not [string]::IsNullOrWhiteSpace("$($payload.commit)")) {
      return "$($payload.commit)"
    }
    if ($null -ne $payload.build -and $null -ne $payload.build.commit) {
      return "$($payload.build.commit)"
    }
    return ""
  } catch {
    return ""
  }
}

$normalizedEnv = $EnvName.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
  Fail("BASE_URL is required. Use -BaseUrl or BASE_URL env var.")
}
$BaseUrl = $BaseUrl.TrimEnd("/")
$StagingBaseUrl = $StagingBaseUrl.TrimEnd("/")

$paymentsProvider = if (-not [string]::IsNullOrWhiteSpace($env:PAYMENTS_PROVIDER)) {
  $env:PAYMENTS_PROVIDER
} elseif (-not [string]::IsNullOrWhiteSpace($env:PAYMENT_PROVIDER)) {
  $env:PAYMENT_PROVIDER
} else {
  ""
}

if ($normalizedEnv -eq "prod" -or $normalizedEnv -eq "production") {
  Require-Env "JWT_SECRET"
  Require-Env "OTP_PROVIDER"
  Require-Env "PAYSTACK_SECRET_KEY"
  Require-Env "PAYSTACK_WEBHOOK_SECRET"
  Require-Env "PAYMENTS_WEBHOOK_SECRET"
  if ([string]::IsNullOrWhiteSpace($paymentsProvider)) {
    Fail("missing required env var: PAYMENTS_PROVIDER (or PAYMENT_PROVIDER)")
  }
  if ([string]::IsNullOrWhiteSpace($StagingBaseUrl)) {
    Fail("staging base URL is required for prod release gate (-StagingBaseUrl)")
  }
} else {
  Require-Env "JWT_SECRET"
  if ([string]::IsNullOrWhiteSpace($paymentsProvider)) {
    Fail("missing required env var: PAYMENTS_PROVIDER (or PAYMENT_PROVIDER)")
  }
}

$adminToken = if (-not [string]::IsNullOrWhiteSpace($env:E2E_ADMIN_TOKEN)) {
  $env:E2E_ADMIN_TOKEN
} else {
  $env:ADMIN_TOKEN
}
if ([string]::IsNullOrWhiteSpace($adminToken)) {
  Fail("set E2E_ADMIN_TOKEN or ADMIN_TOKEN for admin flow smoke checks")
}
$adminTokenEnabled = To-Bool $env:ADMIN_TOKEN_ENABLED
if (-not $adminTokenEnabled) {
  Fail("set ADMIN_TOKEN_ENABLED=true when using ADMIN_TOKEN/E2E_ADMIN_TOKEN for admin smoke checks")
}

if ([string]::IsNullOrWhiteSpace($env:E2E_ACCESS_TOKEN)) {
  Require-Env "E2E_PHONE_E164"
  Require-Env "E2E_OTP_CODE"
}

$targetLabel = if ($normalizedEnv) { $normalizedEnv } else { "staging" }
$smokeBase = $BaseUrl
$smokeEnv = $targetLabel
if ($normalizedEnv -eq "prod" -or $normalizedEnv -eq "production") {
  $smokeBase = $StagingBaseUrl
  $smokeEnv = "staging"
}

Write-Host "[release-gate] target_env=$targetLabel"
Write-Host "[release-gate] target_base=$BaseUrl"
Write-Host "[release-gate] smoke_base=$smokeBase"

Test-Ready -Label $targetLabel -Base $BaseUrl -RequiredHead $RequiredMigrationHead
if ($smokeBase -ne $BaseUrl) {
  Test-Ready -Label "staging" -Base $smokeBase -RequiredHead $RequiredMigrationHead
}

if ($RequireParity -and $smokeBase -ne $BaseUrl) {
  $stagingCommit = Get-Commit -Base $smokeBase
  $targetCommit = Get-Commit -Base $BaseUrl
  if ([string]::IsNullOrWhiteSpace($stagingCommit) -or [string]::IsNullOrWhiteSpace($targetCommit)) {
    Fail("unable to resolve commit for parity check")
  }
  if ($stagingCommit -ne $targetCommit) {
    Fail("commit parity check failed: staging=$stagingCommit target=$targetCommit")
  }
  Write-Host "[release-gate] commit parity verified: $targetCommit"
}

$smokeScript = Join-Path $PSScriptRoot "smoke_e2e.ps1"
$previousAdminToken = $env:E2E_ADMIN_TOKEN
$env:E2E_ADMIN_TOKEN = $adminToken
try {
  Write-Host "[release-gate] running smoke_e2e.ps1 against $smokeBase"
  & $smokeScript -BaseUrl $smokeBase -EnvName $smokeEnv
  if ($LASTEXITCODE -ne 0) {
    Fail("smoke_e2e.ps1 failed with exit code $LASTEXITCODE")
  }
} finally {
  $env:E2E_ADMIN_TOKEN = $previousAdminToken
}

Write-Host "RELEASE GATE: PASS"
