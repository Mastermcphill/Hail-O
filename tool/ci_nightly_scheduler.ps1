$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-NextNightlyRunUtc {
  $now = [DateTime]::UtcNow
  $target = $now.Date.AddHours(2)
  if ($now -ge $target) {
    return $target.AddDays(1)
  }
  return $target
}

Write-Output 'NIGHTLY_SCHEDULER_START'
while ($true) {
  $nextRun = Get-NextNightlyRunUtc
  $sleepSeconds = [int][Math]::Ceiling(($nextRun - [DateTime]::UtcNow).TotalSeconds)
  if ($sleepSeconds -lt 1) {
    $sleepSeconds = 1
  }

  Write-Output ("NIGHTLY_SCHEDULER_SLEEP_UNTIL {0} ({1}s)" -f $nextRun.ToString('o'), $sleepSeconds)
  Start-Sleep -Seconds $sleepSeconds

  $runStart = (Get-Date).ToUniversalTime().ToString('o')
  Write-Output "NIGHTLY_SCHEDULER_RUN_START $runStart"
  & powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'ci_nightly_gate.ps1')
  $runExitCode = $LASTEXITCODE
  Write-Output "NIGHTLY_SCHEDULER_RUN_EXIT $runExitCode"
}
