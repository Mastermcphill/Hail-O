param(
  [ValidateSet('staging', 'production')]
  [string]$Environment = 'staging',
  [switch]$SkipSmoke,
  [switch]$SkipLoadSmoke,
  [switch]$SkipReleaseGate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$artifactDir = Join-Path $root "test_artifacts/ops/go_live_$timestamp"
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

$results = New-Object System.Collections.Generic.List[object]
$hasFailure = $false

function Add-CheckResult {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Status,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $script:results.Add([pscustomobject]@{
      check = $Name
      status = $Status
      message = $Message
    })
  if ($Status -eq 'FAIL') {
    $script:hasFailure = $true
  }
  Write-Output ("[{0}] {1} - {2}" -f $Status, $Name, $Message)
}

function Resolve-BaseUrl {
  param([string]$TargetEnvironment)
  if (-not [string]::IsNullOrWhiteSpace([string]$env:HAILO_API_BASE_URL)) {
    return ([string]$env:HAILO_API_BASE_URL).Trim()
  }
  if ($TargetEnvironment -eq 'production') {
    return 'https://hail-o-api.onrender.com'
  }
  return 'https://hail-o-api-staging.onrender.com'
}

function Read-Env {
  param([Parameter(Mandatory = $true)][string]$Name)
  return [string][Environment]::GetEnvironmentVariable($Name)
}

function Test-HttpEndpoint {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$ExpectedStatus = 200
  )
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 20
    if ($response.StatusCode -ne $ExpectedStatus) {
      return [pscustomobject]@{
        ok = $false
        message = "Expected HTTP $ExpectedStatus but got $($response.StatusCode)"
        body = [string]$response.Content
      }
    }
    return [pscustomobject]@{
      ok = $true
      message = "HTTP $($response.StatusCode)"
      body = [string]$response.Content
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      message = $_.Exception.Message
      body = ''
    }
  }
}

$requiredSecrets = @('JWT_SECRET', 'ALLOWED_ORIGINS', 'SENTRY_DSN')
foreach ($secretName in $requiredSecrets) {
  $value = Read-Env -Name $secretName
  if ([string]::IsNullOrWhiteSpace($value)) {
    Add-CheckResult -Name "env:$secretName" -Status 'FAIL' -Message 'Missing required environment value for go-live gate.'
  } else {
    Add-CheckResult -Name "env:$secretName" -Status 'PASS' -Message 'Configured.'
  }
}

if ($Environment -eq 'staging') {
  $databaseUrl = Read-Env -Name 'HAILO_STAGING_DATABASE_URL'
  if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
    $databaseUrl = Read-Env -Name 'DATABASE_URL'
  }
  if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
    Add-CheckResult -Name 'env:staging_database_url' -Status 'FAIL' -Message 'Set HAILO_STAGING_DATABASE_URL (preferred) or DATABASE_URL.'
  } else {
    Add-CheckResult -Name 'env:staging_database_url' -Status 'PASS' -Message 'Configured.'
  }
}

$expectedHailoEnv = if ($Environment -eq 'production') { 'prod' } else { 'staging' }
$hailoEnv = Read-Env -Name 'HAILO_ENV'
if ([string]::IsNullOrWhiteSpace($hailoEnv)) {
  Add-CheckResult -Name 'env:HAILO_ENV' -Status 'FAIL' -Message "Missing. Expected '$expectedHailoEnv'."
} elseif ($hailoEnv.Trim().ToLowerInvariant() -ne $expectedHailoEnv) {
  Add-CheckResult -Name 'env:HAILO_ENV' -Status 'FAIL' -Message "Expected '$expectedHailoEnv', got '$hailoEnv'."
} else {
  Add-CheckResult -Name 'env:HAILO_ENV' -Status 'PASS' -Message "Matched '$expectedHailoEnv'."
}

$baseUrl = Resolve-BaseUrl -TargetEnvironment $Environment
Add-CheckResult -Name 'target:base_url' -Status 'PASS' -Message $baseUrl

foreach ($path in @('/healthz', '/api/healthz', '/version')) {
  $url = "$baseUrl$path"
  $result = Test-HttpEndpoint -Url $url -ExpectedStatus 200
  if (-not $result.ok) {
    Add-CheckResult -Name "http:$path" -Status 'FAIL' -Message $result.message
  } else {
    Add-CheckResult -Name "http:$path" -Status 'PASS' -Message $result.message
    if ($path -eq '/version') {
      try {
        $json = $result.body | ConvertFrom-Json
        $commit = [string]$json.commit
        if ([string]::IsNullOrWhiteSpace($commit)) {
          Add-CheckResult -Name 'http:/version.commit' -Status 'FAIL' -Message 'Missing commit field in /version payload.'
        } else {
          Add-CheckResult -Name 'http:/version.commit' -Status 'PASS' -Message "commit=$commit"
        }
      } catch {
        Add-CheckResult -Name 'http:/version.parse' -Status 'FAIL' -Message 'Unable to parse /version response JSON.'
      }
    }
  }
}

if (-not $SkipSmoke) {
  $env:HAILO_API_BASE_URL = $baseUrl
  $env:ENV = $Environment
  $smokeArtifactDir = Join-Path $artifactDir 'smoke'
  $env:HAILO_SMOKE_ARTIFACT_DIR = $smokeArtifactDir
  New-Item -ItemType Directory -Path $smokeArtifactDir -Force | Out-Null
  try {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
    if ($LASTEXITCODE -ne 0) {
      Add-CheckResult -Name 'smoke:backend' -Status 'FAIL' -Message "tool/smoke_backend.ps1 exit=$LASTEXITCODE"
    } else {
      Add-CheckResult -Name 'smoke:backend' -Status 'PASS' -Message 'Smoke suite passed.'
    }
  } catch {
    Add-CheckResult -Name 'smoke:backend' -Status 'FAIL' -Message $_.Exception.Message
  }
} else {
  Add-CheckResult -Name 'smoke:backend' -Status 'SKIP' -Message 'Skipped by flag.'
}

if (-not $SkipLoadSmoke) {
  $env:HAILO_API_BASE_URL = $baseUrl
  $env:ENV = $Environment
  $loadArtifactDir = Join-Path $artifactDir 'load_smoke'
  $env:HAILO_LOAD_SMOKE_ARTIFACT_DIR = $loadArtifactDir
  New-Item -ItemType Directory -Path $loadArtifactDir -Force | Out-Null
  try {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'load_smoke.ps1')
    if ($LASTEXITCODE -ne 0) {
      Add-CheckResult -Name 'smoke:load' -Status 'FAIL' -Message "tool/load_smoke.ps1 exit=$LASTEXITCODE"
    } else {
      Add-CheckResult -Name 'smoke:load' -Status 'PASS' -Message 'Load smoke passed.'
    }
  } catch {
    Add-CheckResult -Name 'smoke:load' -Status 'FAIL' -Message $_.Exception.Message
  }
} else {
  Add-CheckResult -Name 'smoke:load' -Status 'SKIP' -Message 'Skipped by flag.'
}

if ($Environment -eq 'staging' -and -not $SkipReleaseGate) {
  try {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release_gate.ps1')
    if ($LASTEXITCODE -ne 0) {
      Add-CheckResult -Name 'gate:release' -Status 'FAIL' -Message "tool/release_gate.ps1 exit=$LASTEXITCODE"
    } else {
      Add-CheckResult -Name 'gate:release' -Status 'PASS' -Message 'Release gate passed.'
    }
  } catch {
    Add-CheckResult -Name 'gate:release' -Status 'FAIL' -Message $_.Exception.Message
  }
} elseif ($Environment -eq 'staging') {
  Add-CheckResult -Name 'gate:release' -Status 'SKIP' -Message 'Skipped by flag.'
}

$summary = [ordered]@{
  generated_at = (Get-Date).ToString('o')
  environment = $Environment
  base_url = $baseUrl
  failed = $hasFailure
  checks = $results
}

$summaryPath = Join-Path $artifactDir 'go_live_summary.json'
($summary | ConvertTo-Json -Depth 8) | Set-Content -Path $summaryPath -Encoding UTF8
Write-Output "go_live_summary=$summaryPath"

if ($hasFailure) {
  Write-Output 'GO-LIVE CHECK: FAIL'
  exit 1
}

Write-Output 'GO-LIVE CHECK: PASS'
exit 0
