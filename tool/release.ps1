$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Push-Location $root
try {
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'release_gate.ps1')
  if ($LASTEXITCODE -ne 0) {
    exit 1
  }

  $today = Get-Date -Format 'yyyy.MM.dd'
  $tagPrefix = "v$today."
  $tagPattern = "$tagPrefix*"
  $existingTags = @(& git tag --list $tagPattern)
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to list tags matching $tagPattern"
  }

  $maxN = 0
  $escapedPrefix = [regex]::Escape($tagPrefix)
  foreach ($tag in $existingTags) {
    $tagText = ([string]$tag).Trim()
    if ($tagText -match "^$escapedPrefix(\d+)$") {
      $value = 0
      if ([int]::TryParse($Matches[1], [ref]$value) -and $value -gt $maxN) {
        $maxN = $value
      }
    }
  }

  $nextN = $maxN + 1
  $releaseTag = "$tagPrefix$nextN"

  $commit = [string](@(& git rev-parse HEAD) | Select-Object -First 1)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
    throw 'Failed to resolve current git commit.'
  }
  $commit = $commit.Trim()

  & git tag -a $releaseTag -m "Release $releaseTag" $commit
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create annotated tag $releaseTag"
  }

  & git push origin $releaseTag
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to push tag $releaseTag to origin"
  }

  Write-Output "RELEASE READY: $releaseTag @ $commit"
  Write-Output 'Deploy latest commit on Render for hail-o-api (prod).'
} finally {
  Pop-Location
}
