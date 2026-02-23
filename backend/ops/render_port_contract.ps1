$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$backendDir = Join-Path $repoRoot "backend"
$port = 9999
$logFile = Join-Path $env:TEMP ("render_port_contract_" + [Guid]::NewGuid().ToString("N") + ".log")
$errFile = Join-Path $env:TEMP ("render_port_contract_" + [Guid]::NewGuid().ToString("N") + ".err.log")

$env:PORT = "$port"
if (-not $env:BACKEND_DB_MODE) {
  $env:BACKEND_DB_MODE = "sqlite"
}

$proc = $null

try {
  $proc = Start-Process `
    -FilePath "dart" `
    -ArgumentList @("run", "bin/server.dart") `
    -WorkingDirectory $backendDir `
    -RedirectStandardOutput $logFile `
    -RedirectStandardError $errFile `
    -PassThru

  $content = ""
  $listener = $null
  for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Milliseconds 500
    $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (Test-Path $logFile) {
      $content = Get-Content $logFile -Raw
    }
    if ($listener) {
      break
    }
  }

  if (-not $listener) {
    $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { "" }
    throw "server did not bind to port ${port}`nstdout:`n$content`nstderr:`n$stderr"
  }

  $addresses = @($listener | Select-Object -ExpandProperty LocalAddress -Unique)
  if (-not ($addresses -contains "0.0.0.0")) {
    $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { "" }
    throw "listener not bound to 0.0.0.0 on port ${port}. addresses=$($addresses -join ',')`nstdout:`n$content`nstderr:`n$stderr"
  }

  $healthz = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 10
  if ($healthz.StatusCode -ne 200) {
    throw "/healthz returned $($healthz.StatusCode)"
  }

  $apiHealthz = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/api/healthz" -TimeoutSec 10
  if ($apiHealthz.StatusCode -ne 200) {
    throw "/api/healthz returned $($apiHealthz.StatusCode)"
  }

  Write-Host "render port contract passed"
}
finally {
  if ($proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
  }
  $listener = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
  if ($listener) {
    $pids = @($listener | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($ownerPid in $pids) {
      Stop-Process -Id $ownerPid -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item -Force $logFile -ErrorAction SilentlyContinue
  Remove-Item -Force $errFile -ErrorAction SilentlyContinue
}
