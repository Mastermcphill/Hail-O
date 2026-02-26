param(
  [string]$RedisUrl = "",
  [int]$StartupTimeoutSeconds = 60,
  [switch]$SkipCaseC
)

$ErrorActionPreference = "Stop"

function To-Bool([object]$Value) {
  if ($null -eq $Value) {
    return $false
  }
  $normalized = "$Value".Trim().ToLowerInvariant()
  return @("1", "true", "yes", "y", "on") -contains $normalized
}

function New-ArtifactDirectory {
  $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $base = Join-Path $PSScriptRoot "test_artifacts/redis/$timestamp"
  New-Item -ItemType Directory -Path $base -Force | Out-Null
  return $base
}

function Write-Artifact([string]$Path, [object]$Payload) {
  $json = $Payload | ConvertTo-Json -Depth 20
  Set-Content -Path $Path -Value $json -Encoding UTF8
}

function Get-FreePort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()
  return $port
}

function Invoke-ReadyOnce([string]$BaseUrl) {
  $base = $BaseUrl.TrimEnd("/")
  $paths = @("/ready", "/api/ready")
  foreach ($path in $paths) {
    $target = "$base$path"
    $escapedTarget = $target.Replace('"', '""')
    $command = "curl -sS -m 5 -w __STATUS__:^%{http_code} `"$escapedTarget`" 2>NUL"
    $responseText = & cmd.exe /d /c $command
    $curlExitCode = $LASTEXITCODE
    if ($curlExitCode -ne 0 -or $null -eq $responseText) {
      continue
    }
    $normalized = "$responseText".Trim()
    $statusMatch = [regex]::Match($normalized, "__STATUS__:(\d{3})$")
    if (-not $statusMatch.Success) {
      continue
    }
    $status = [int]$statusMatch.Groups[1].Value
    if ($status -eq 404) {
      continue
    }
    $raw = $normalized.Substring(0, $statusMatch.Index).Trim()
    $body = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
      try {
        $body = $raw | ConvertFrom-Json
      } catch {
        $body = $null
      }
    }
    return [ordered]@{
      status = $status
      path = $path
      body = $body
      raw = $raw
    }
  }
  return [ordered]@{
    status = 0
    path = ""
    body = $null
    raw = ""
  }
}

function Wait-ForReady([string]$BaseUrl, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $last = $null
  while ((Get-Date) -lt $deadline) {
    $last = Invoke-ReadyOnce -BaseUrl $BaseUrl
    if ([int]$last.status -ne 0) {
      return $last
    }
    Start-Sleep -Seconds 1
  }
  if ($null -eq $last) {
    $last = [ordered]@{
      status = 0
      path = ""
      body = $null
      raw = ""
    }
  }
  return $last
}

function Start-BackendProcess {
  param(
    [string]$CaseName,
    [string]$BackendDir,
    [string]$ArtifactDir,
    [string]$DartExecutable,
    [hashtable]$EnvironmentOverrides
  )

  $port = Get-FreePort
  $stdoutPath = Join-Path $ArtifactDir "$CaseName.stdout.log"
  $stderrPath = Join-Path $ArtifactDir "$CaseName.stderr.log"
  Set-Content -Path $stdoutPath -Value "" -Encoding UTF8
  Set-Content -Path $stderrPath -Value "" -Encoding UTF8

  $effectiveEnv = [ordered]@{
    "ENV" = "development"
    "BACKEND_DB_MODE" = "sqlite"
    "PORT" = "$port"
    "RATE_LIMIT_ENABLED" = "false"
  }
  foreach ($key in $EnvironmentOverrides.Keys) {
    $effectiveEnv[$key] = $EnvironmentOverrides[$key]
  }

  $setCommands = New-Object System.Collections.Generic.List[string]
  foreach ($key in $effectiveEnv.Keys) {
    $value = $effectiveEnv[$key]
    if ($null -eq $value) {
      $setCommands.Add(('set "{0}="' -f $key))
    } else {
      $safe = "$value".Replace('"', '""')
      $setCommands.Add(('set "{0}={1}"' -f $key, $safe))
    }
  }
  $safeDartPath = $DartExecutable.Replace('"', '""')
  $safeStdoutPath = $stdoutPath.Replace('"', '""')
  $safeStderrPath = $stderrPath.Replace('"', '""')
  $command = (
    '{0} && "{1}" run main.dart 1>"{2}" 2>"{3}"' -f
        ($setCommands -join ' && '),
        $safeDartPath,
        $safeStdoutPath,
        $safeStderrPath
  )

  $process = Start-Process `
    -FilePath "cmd.exe" `
    -ArgumentList @("/d", "/c", $command) `
    -WorkingDirectory $BackendDir `
    -PassThru `
    -WindowStyle Hidden

  return [ordered]@{
    case_name = $CaseName
    port = $port
    base_url = "http://127.0.0.1:$port"
    process = $process
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
  }
}

function Resolve-DartExecutable {
  $command = Get-Command "dart" -ErrorAction SilentlyContinue
  if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace($command.Source)) {
    return $command.Source
  }
  $batCommand = Get-Command "dart.bat" -ErrorAction SilentlyContinue
  if ($null -ne $batCommand -and -not [string]::IsNullOrWhiteSpace($batCommand.Source)) {
    return $batCommand.Source
  }
  throw "Could not locate Dart executable. Ensure Dart SDK is installed and on PATH."
}

function Stop-BackendProcess([hashtable]$Run) {
  $process = $Run.process
  Write-Host "[redis-matrix] stopping process id=$($process.Id)"
  if (-not $process.HasExited) {
    try {
      & cmd.exe /d /c "taskkill /PID $($process.Id) /T /F" | Out-Null
    } catch {
      # no-op
    }
    try {
      [void]$process.WaitForExit(5000)
    } catch {
      # no-op
    }
  }
  Write-Host "[redis-matrix] process stopped id=$($process.Id) exited=$($process.HasExited)"
  return [ordered]@{
    exit_code = if ($process.HasExited) { [int]$process.ExitCode } else { -1 }
    stdout_path = $Run.stdout_path
    stderr_path = $Run.stderr_path
  }
}

function Test-RedisReachable([string]$TargetRedisUrl) {
  if ([string]::IsNullOrWhiteSpace($TargetRedisUrl)) {
    return [ordered]@{
      ok = $false
      reason = "REDIS_URL was not provided."
    }
  }
  try {
    $uri = [Uri]$TargetRedisUrl
  } catch {
    return [ordered]@{
      ok = $false
      reason = "Invalid REDIS_URL format: $TargetRedisUrl"
    }
  }
  $scheme = $uri.Scheme.Trim().ToLowerInvariant()
  if ($scheme -ne "redis" -and $scheme -ne "rediss") {
    return [ordered]@{
      ok = $false
      reason = "Unsupported Redis URL scheme: $($uri.Scheme)"
    }
  }
  if ([string]::IsNullOrWhiteSpace($uri.Host)) {
    return [ordered]@{
      ok = $false
      reason = "Redis URL must include a host."
    }
  }
  $port = if ($uri.IsDefaultPort) { 6379 } else { $uri.Port }
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $connectTask = $client.ConnectAsync($uri.Host, $port)
    if (-not $connectTask.Wait(1000)) {
      return [ordered]@{
        ok = $false
        reason = "Could not connect to $($uri.Host):$port within 1s."
      }
    }
    return [ordered]@{
      ok = $true
      reason = ""
    }
  } catch {
    return [ordered]@{
      ok = $false
      reason = $_.Exception.Message
    }
  } finally {
    $client.Dispose()
  }
}

$artifactDir = New-ArtifactDirectory
$backendDir = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$dartExecutable = Resolve-DartExecutable
$resolvedRedisUrl = if (-not [string]::IsNullOrWhiteSpace($RedisUrl)) {
  $RedisUrl
} elseif (-not [string]::IsNullOrWhiteSpace($env:REDIS_URL)) {
  $env:REDIS_URL
} else {
  "redis://127.0.0.1:6379/0"
}

$results = New-Object System.Collections.Generic.List[object]
$overallFail = $false

Write-Host "[redis-matrix] artifacts: $artifactDir"

# Case A: REDIS_ENABLED unset/false, bypass mode.
$caseATimer = [System.Diagnostics.Stopwatch]::StartNew()
$caseAResult = [ordered]@{
  id = "case_a"
  status = "fail"
  ok = $false
  details = ""
}
$caseARun = $null
try {
  Write-Host "[redis-matrix] case_a start"
  $caseARun = Start-BackendProcess `
    -CaseName "case_a_bypass" `
    -BackendDir $backendDir `
    -ArtifactDir $artifactDir `
    -DartExecutable $dartExecutable `
    -EnvironmentOverrides @{
      "REDIS_ENABLED" = "false"
      "REDIS_URL" = $null
    }
  $ready = Wait-ForReady -BaseUrl $caseARun.base_url -TimeoutSeconds $StartupTimeoutSeconds
  Write-Host "[redis-matrix] case_a ready status=$($ready.status)"
  $body = $ready.body
  $status = [int]$ready.status
  $okValue = if ($null -ne $body) { $body.ok } else { $false }
  $okFlag = To-Bool $okValue
  $readyFlag = if ($null -ne $body -and $null -ne $body.ready) {
    To-Bool $body.ready
  } else {
    $okFlag
  }
  $redisEnabledValue = if ($null -ne $body) { $body.redis_enabled } else { $false }
  $redisConfiguredValue = if ($null -ne $body) { $body.redis_configured } else { $false }
  $redisEnabled = To-Bool $redisEnabledValue
  $redisConfigured = To-Bool $redisConfiguredValue
  $caseAResult.ok = ($status -eq 200 -and $okFlag -and $readyFlag -and -not $redisEnabled -and -not $redisConfigured)
  $caseAResult.status = if ($caseAResult.ok) { "pass" } else { "fail" }
  $caseAResult.details = "status=$status ok=$okFlag ready=$readyFlag redis_enabled=$redisEnabled redis_configured=$redisConfigured"
  $caseAResult.ready = $ready
} finally {
  if ($null -ne $caseARun) {
    Write-Host "[redis-matrix] case_a finalizing"
    $output = Stop-BackendProcess -Run $caseARun
    $fatalRedisLog = $false
    if (Test-Path $output.stderr_path) {
      $fatalRedisLog = Select-String `
        -Path $output.stderr_path `
        -Pattern "(?i)fatal:.*redis" `
        -Quiet `
        -ErrorAction SilentlyContinue
    }
    if ($fatalRedisLog) {
      $caseAResult.ok = $false
      $caseAResult.status = "fail"
      $caseAResult.details = "$($caseAResult.details); fatal redis log detected"
    }
    $caseAResult.output = $output
  }
}
$caseATimer.Stop()
$caseAResult.duration_ms = $caseATimer.ElapsedMilliseconds
Write-Host "[redis-matrix] case_a done status=$($caseAResult.status)"
$results.Add($caseAResult)
Write-Artifact -Path (Join-Path $artifactDir "case_a_bypass.json") -Payload $caseAResult
if (-not $caseAResult.ok) {
  $overallFail = $true
}

# Case B: REDIS_ENABLED=true and REDIS_URL missing, fail fast.
$caseBTimer = [System.Diagnostics.Stopwatch]::StartNew()
$caseBResult = [ordered]@{
  id = "case_b"
  status = "fail"
  ok = $false
  details = ""
}
$caseBRun = $null
try {
  Write-Host "[redis-matrix] case_b start"
  $caseBRun = Start-BackendProcess `
    -CaseName "case_b_enabled_missing_url" `
    -BackendDir $backendDir `
    -ArtifactDir $artifactDir `
    -DartExecutable $dartExecutable `
    -EnvironmentOverrides @{
      "REDIS_ENABLED" = "true"
      "REDIS_URL" = $null
    }
  $caseBWaitSeconds = [Math]::Max(30, $StartupTimeoutSeconds * 2)
  $exited = $caseBRun.process.WaitForExit($caseBWaitSeconds * 1000)
  Write-Host "[redis-matrix] case_b exited=$exited"
  $output = Stop-BackendProcess -Run $caseBRun
  $messageSeen = $false
  if (Test-Path $output.stderr_path) {
    $messageSeen = Select-String `
      -Path $output.stderr_path `
      -Pattern "REDIS_ENABLED=true requires REDIS_URL" `
      -Quiet `
      -ErrorAction SilentlyContinue
  }
  if (-not $messageSeen -and (Test-Path $output.stdout_path)) {
    $messageSeen = Select-String `
      -Path $output.stdout_path `
      -Pattern "REDIS_ENABLED=true requires REDIS_URL" `
      -Quiet `
      -ErrorAction SilentlyContinue
  }
  $exitCode = [int]$output.exit_code
  $caseBResult.ok = ($exited -and $exitCode -ne 0 -and $messageSeen)
  $caseBResult.status = if ($caseBResult.ok) { "pass" } else { "fail" }
  $caseBResult.details = "exited=$exited exit_code=$exitCode message_seen=$messageSeen"
  $caseBResult.output = $output
} finally {
  if ($null -ne $caseBRun -and -not $caseBRun.process.HasExited) {
    $output = Stop-BackendProcess -Run $caseBRun
    $caseBResult.output = $output
  }
}
$caseBTimer.Stop()
$caseBResult.duration_ms = $caseBTimer.ElapsedMilliseconds
Write-Host "[redis-matrix] case_b done status=$($caseBResult.status)"
$results.Add($caseBResult)
Write-Artifact -Path (Join-Path $artifactDir "case_b_enabled_missing_url.json") -Payload $caseBResult
if (-not $caseBResult.ok) {
  $overallFail = $true
}

# Case C: REDIS_ENABLED=true with URL, redis must be ready.
$caseCTimer = [System.Diagnostics.Stopwatch]::StartNew()
$caseCResult = [ordered]@{
  id = "case_c"
  status = "skipped"
  ok = $true
  details = ""
  redis_url = $resolvedRedisUrl
}

if ($SkipCaseC.IsPresent) {
  $caseCResult.details = "Skipped by -SkipCaseC."
} else {
  $reachable = Test-RedisReachable -TargetRedisUrl $resolvedRedisUrl
  if (-not $reachable.ok) {
    $caseCResult.details = "SKIP: redis unavailable. $($reachable.reason) Start Redis (for example: docker run -p 6379:6379 redis) and rerun."
  } else {
    $caseCRun = $null
    try {
      $caseCRun = Start-BackendProcess `
        -CaseName "case_c_enabled_with_url" `
        -BackendDir $backendDir `
        -ArtifactDir $artifactDir `
        -DartExecutable $dartExecutable `
        -EnvironmentOverrides @{
          "REDIS_ENABLED" = "true"
          "REDIS_URL" = $resolvedRedisUrl
        }
      $ready = Wait-ForReady -BaseUrl $caseCRun.base_url -TimeoutSeconds $StartupTimeoutSeconds
      $body = $ready.body
      $status = [int]$ready.status
      $okValue = if ($null -ne $body) { $body.ok } else { $false }
      $okFlag = To-Bool $okValue
      $readyFlag = if ($null -ne $body -and $null -ne $body.ready) {
        To-Bool $body.ready
      } else {
        $okFlag
      }
      $redisEnabledValue = if ($null -ne $body) { $body.redis_enabled } else { $false }
      $redisConfiguredValue = if ($null -ne $body) { $body.redis_configured } else { $false }
      $redisReadyValue = if ($null -ne $body) { $body.redis_ready } else { $false }
      $redisEnabled = To-Bool $redisEnabledValue
      $redisConfigured = To-Bool $redisConfiguredValue
      $redisReady = To-Bool $redisReadyValue
      $caseCResult.ok = ($status -eq 200 -and $okFlag -and $readyFlag -and $redisEnabled -and $redisConfigured -and $redisReady)
      $caseCResult.status = if ($caseCResult.ok) { "pass" } else { "fail" }
      $caseCResult.details = "status=$status ok=$okFlag ready=$readyFlag redis_enabled=$redisEnabled redis_configured=$redisConfigured redis_ready=$redisReady"
      $caseCResult.ready = $ready
    } finally {
      if ($null -ne $caseCRun) {
        $output = Stop-BackendProcess -Run $caseCRun
        $caseCResult.output = $output
      }
    }
    if (-not $caseCResult.ok) {
      $overallFail = $true
    }
  }
}

$caseCTimer.Stop()
$caseCResult.duration_ms = $caseCTimer.ElapsedMilliseconds
$results.Add($caseCResult)
Write-Artifact -Path (Join-Path $artifactDir "case_c_enabled_with_url.json") -Payload $caseCResult

$summary = [ordered]@{
  ok = (-not $overallFail)
  cases = $results
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
}
Write-Artifact -Path (Join-Path $artifactDir "summary.json") -Payload $summary

if ($summary.ok) {
  Write-Host "[redis-matrix] PASS"
  exit 0
}

Write-Host "[redis-matrix] FAIL"
exit 1
