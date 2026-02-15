$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$steps = @()
$failed = $false

function Invoke-GateStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action
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
  Invoke-GateStep -Name 'Render blueprint verification' -Action {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_render_blueprint.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "render blueprint verification failed with exit code $LASTEXITCODE"
    }
  }

  Invoke-GateStep -Name 'Backend tests (dart test)' -Action {
    Push-Location (Join-Path $root 'backend')
    try {
      dart test
      if ($LASTEXITCODE -ne 0) {
        throw "backend dart test failed with exit code $LASTEXITCODE"
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
