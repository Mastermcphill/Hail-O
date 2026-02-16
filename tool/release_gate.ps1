$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$steps = @()
$failed = $false

function Invoke-GateStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [switch]$StopOnFail
  )

  Write-Output "=== $Name ==="
  try {
    & $Action
    $script:steps += [pscustomobject]@{ Name = $Name; Status = 'PASS' }
  } catch {
    $script:steps += [pscustomobject]@{ Name = $Name; Status = 'FAIL' }
    $script:failed = $true
    Write-Output "Step failed: $Name"
    Write-Output $_
    if ($StopOnFail) {
      throw
    }
  }
}

function Add-SkippedStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Reason
  )
  Write-Output "=== $Name (SKIPPED) ==="
  Write-Output $Reason
  $script:steps += [pscustomobject]@{ Name = $Name; Status = 'SKIP' }
}

Push-Location $root
try {
  Invoke-GateStep -Name 'Render settings verification' -StopOnFail -Action {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_render_settings.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "render settings verification failed with exit code $LASTEXITCODE"
    }
  }

  Invoke-GateStep -Name 'Staging routing verification' -StopOnFail -Action {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_staging_routing.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "staging routing verification failed with exit code $LASTEXITCODE"
    }
  }

  if ($env:HAILO_REQUIRE_RUNTIME_MARKER -eq '1') {
    Invoke-GateStep -Name 'Render runtime sanity (/health marker)' -StopOnFail -Action {
      powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'sanity_render_runtime.ps1')
      if ($LASTEXITCODE -ne 0) {
        throw "render runtime sanity failed with exit code $LASTEXITCODE"
      }
    }
  } else {
    Add-SkippedStep -Name 'Render runtime sanity (/health marker)' -Reason 'Set HAILO_REQUIRE_RUNTIME_MARKER=1 to enforce runtime marker check.'
  }

  Invoke-GateStep -Name 'Backend checks (pub get + analyze + test)' -Action {
    Push-Location (Join-Path $root 'backend')
    try {
      dart pub get
      if ($LASTEXITCODE -ne 0) {
        throw "backend dart pub get failed with exit code $LASTEXITCODE"
      }
      dart analyze
      if ($LASTEXITCODE -ne 0) {
        throw "backend dart analyze failed with exit code $LASTEXITCODE"
      }
      dart test
      if ($LASTEXITCODE -ne 0) {
        throw "backend dart test failed with exit code $LASTEXITCODE"
      }
      dart run tool/check_contract_breaking.dart
      if ($LASTEXITCODE -ne 0) {
        throw "backend contract breaking check failed with exit code $LASTEXITCODE"
      }
    } finally {
      Pop-Location
    }
  }

  Invoke-GateStep -Name 'Flutter tests (flutter test)' -Action {
    flutter test
    if ($LASTEXITCODE -ne 0) {
      throw "flutter test failed with exit code $LASTEXITCODE"
    }
  }

  Invoke-GateStep -Name 'Staging smoke (PowerShell)' -Action {
    $env:HAILO_API_BASE_URL = 'https://hail-o-api-staging.onrender.com'
    $env:ENV = 'staging'
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "staging smoke failed with exit code $LASTEXITCODE"
    }
  }

  if ($env:HAILO_ALLOW_PROD_SMOKE -eq '1') {
    Invoke-GateStep -Name 'Production smoke (PowerShell)' -Action {
      $env:HAILO_API_BASE_URL = 'https://hail-o-api.onrender.com'
      $env:ENV = 'production'
      $env:HAILO_ALLOW_PROD_SMOKE = '1'
      powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
      if ($LASTEXITCODE -ne 0) {
        throw "production smoke failed with exit code $LASTEXITCODE"
      }
    }
  } else {
    Add-SkippedStep -Name 'Production smoke (PowerShell)' -Reason 'Set HAILO_ALLOW_PROD_SMOKE=1 to run production smoke.'
  }
} finally {
  Pop-Location
}

Write-Output "`n=== Release Gate Summary ==="
foreach ($step in $steps) {
  Write-Output ("{0,-35} {1}" -f $step.Name, $step.Status)
}

if ($failed) {
  Write-Output 'RELEASE GATE: FAIL'
  exit 1
}

Write-Output 'RELEASE GATE: PASS'
exit 0
