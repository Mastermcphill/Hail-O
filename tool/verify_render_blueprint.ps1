$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$renderPath = Join-Path $root 'render.yaml'

if (-not (Test-Path $renderPath)) {
  throw "render.yaml not found at $renderPath"
}

$content = Get-Content $renderPath -Raw
if ($content -match '(?m)^\s*(dockerCommand|startCommand)\s*:') {
  throw 'render.yaml must not define dockerCommand/startCommand overrides; use Dockerfile CMD only.'
}

$lines = Get-Content $renderPath
$services = @()
$inServices = $false
$current = $null

function Add-ServiceBlock {
  param([hashtable]$Service)
  if ($Service -and $Service.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace($Service.name)) {
    $script:services += $Service
  }
}

foreach ($line in $lines) {
  if ($line -match '^\s*services:\s*$') {
    $inServices = $true
    continue
  }
  if ($inServices -and $line -match '^[A-Za-z_][A-Za-z0-9_]*:\s*$') {
    Add-ServiceBlock -Service $current
    $current = $null
    $inServices = $false
    continue
  }
  if (-not $inServices) {
    continue
  }

  if ($line -match '^ {2}-\s*type:\s*(.+?)\s*$') {
    Add-ServiceBlock -Service $current
    $current = @{
      type = $Matches[1].Trim()
      name = ''
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
  if ($line -match '^ {4}rootDir:\s*(.+?)\s*$') {
    $current.rootDir = $Matches[1].Trim()
    continue
  }
  if ($line -match '^ {4}dockerfilePath:\s*(.+?)\s*$') {
    $current.dockerfilePath = $Matches[1].Trim()
    continue
  }
}
Add-ServiceBlock -Service $current

if ($services.Count -eq 0) {
  throw 'No services parsed from render.yaml'
}

function Find-Service([string]$serviceName) {
  return $services | Where-Object { $_.name -eq $serviceName } | Select-Object -First 1
}

function Assert-Service {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Type,
    [Parameter(Mandatory = $true)][string]$DockerfilePath,
    [Parameter(Mandatory = $true)][string]$RootDir
  )
  $service = Find-Service -serviceName $Name
  if ($null -eq $service) {
    throw "Missing required Render service '$Name'"
  }
  if ($service.type -ne $Type) {
    throw "Service '$Name' must be type '$Type' (found '$($service.type)')"
  }
  if ($service.rootDir -ne $RootDir) {
    throw "Service '$Name' must use rootDir '$RootDir' (found '$($service.rootDir)')"
  }
  if ($service.dockerfilePath -ne $DockerfilePath) {
    throw "Service '$Name' must use dockerfilePath '$DockerfilePath' (found '$($service.dockerfilePath)')"
  }
  $dockerPath = Join-Path $root $DockerfilePath
  if (-not (Test-Path $dockerPath)) {
    throw "dockerfilePath for '$Name' does not exist at $dockerPath"
  }
}

Assert-Service -Name 'hail-o-ci' -Type 'worker' -DockerfilePath 'Dockerfile.ci' -RootDir '.'
Assert-Service -Name 'hail-o-api' -Type 'web' -DockerfilePath 'backend/Dockerfile' -RootDir '.'
Assert-Service -Name 'hail-o-api-staging' -Type 'web' -DockerfilePath 'backend/Dockerfile' -RootDir '.'

Write-Output 'Render blueprint verification: PASS'
foreach ($service in $services) {
  Write-Output ("- {0} ({1}) rootDir={2} dockerfilePath={3}" -f $service.name, $service.type, $service.rootDir, $service.dockerfilePath)
}
