$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$renderPath = Join-Path $root 'render.yaml'

if (-not (Test-Path $renderPath)) {
  throw "render.yaml not found at $renderPath"
}

powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify_render_blueprint.ps1')
if ($LASTEXITCODE -ne 0) {
  throw "verify_render_blueprint.ps1 failed with exit code $LASTEXITCODE"
}

$lines = Get-Content $renderPath
$services = @()
$inServices = $false
$current = $null

function Add-Service {
  param([hashtable]$Service)
  if ($Service -and $Service.name) {
    $script:services += $Service
  }
}

foreach ($line in $lines) {
  if ($line -match '^\s*services:\s*$') {
    $inServices = $true
    continue
  }
  if ($inServices -and $line -match '^[A-Za-z_][A-Za-z0-9_]*:\s*$') {
    Add-Service -Service $current
    $current = $null
    $inServices = $false
    continue
  }
  if (-not $inServices) {
    continue
  }

  if ($line -match '^ {2}-\s*type:\s*(.+?)\s*$') {
    Add-Service -Service $current
    $current = @{
      type = $Matches[1].Trim()
      name = ''
      env = ''
      rootDir = ''
      dockerfilePath = ''
    }
    continue
  }
  if ($null -eq $current) {
    continue
  }
  if ($line -match '^ {4}name:\s*(.+?)\s*$') {
    $current.name = $Matches[1].Trim()
    continue
  }
  if ($line -match '^ {4}env:\s*(.+?)\s*$') {
    $current.env = $Matches[1].Trim()
    continue
  }
  if ($line -match '^ {4}rootDir:\s*(.+?)\s*$') {
    $current.rootDir = $Matches[1].Trim()
    continue
  }
  if ($line -match '^ {4}dockerfilePath:\s*(.+?)\s*$') {
    $current.dockerfilePath = $Matches[1].Trim()
    continue
  }
}
Add-Service -Service $current

function Assert-ServiceDocker {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$DockerfilePath
  )

  $service = $services | Where-Object { $_.name -eq $Name } | Select-Object -First 1
  if ($null -eq $service) {
    throw "Missing expected service '$Name'"
  }
  if ($service.env -ne 'docker') {
    throw "Service '$Name' must run with env=docker (found '$($service.env)')"
  }
  if ($service.rootDir -ne '.') {
    throw "Service '$Name' must use rootDir='.' (found '$($service.rootDir)')"
  }
  if ($service.dockerfilePath -ne $DockerfilePath) {
    throw "Service '$Name' must use dockerfilePath='$DockerfilePath' (found '$($service.dockerfilePath)')"
  }
}

Assert-ServiceDocker -Name 'hail-o-ci' -DockerfilePath 'Dockerfile.ci'
Assert-ServiceDocker -Name 'hail-o-api' -DockerfilePath 'backend/Dockerfile'
Assert-ServiceDocker -Name 'hail-o-api-staging' -DockerfilePath 'backend/Dockerfile'

Write-Output 'Render settings verification: PASS'
Write-Output 'Dashboard checks (manual, required):'
Write-Output '- Render > Service > Settings > Build & Deploy'
Write-Output '- Root Directory must be "." (repo root).'
Write-Output '- Environment must be "Docker".'
Write-Output '- Start Command must be empty.'
Write-Output '- Docker Command must be empty.'
