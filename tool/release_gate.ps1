param(
  [string]$ExpectedStagingSchema = 'hailo_staging',
  [string]$ExpectedStagingCommit = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'

$requestedProdSmoke = [string]$env:HAILO_ALLOW_PROD_SMOKE
$requestedProdConfirm = [string]$env:HAILO_PROD_CONFIRM

foreach ($variableName in @('HAILO_API_BASE_URL', 'ENV', 'HAILO_ALLOW_PROD_SMOKE')) {
  Remove-Item "Env:$variableName" -ErrorAction SilentlyContinue
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$artifactDir = Join-Path $root "test_artifacts/ops/$timestamp"
New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null

$steps = @()
$failed = $false
$script:stagingDatabaseUrlForProbe = ''
$script:stagingDatabaseUrlSslmode = ''

function Convert-ToStepLogFileName {
  param([Parameter(Mandatory = $true)][string]$Name)

  $slug = ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '_').Trim('_')
  if ([string]::IsNullOrWhiteSpace($slug)) {
    $slug = 'step'
  }
  return "$slug.log"
}

function Invoke-GateStep {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [switch]$StopOnFail
  )

  $logName = Convert-ToStepLogFileName -Name $Name
  $logPath = Join-Path $script:artifactDir $logName
  "=== $Name ===" | Tee-Object -FilePath $logPath
  try {
    & $Action *>&1 | Tee-Object -FilePath $logPath -Append
    $script:steps += [pscustomobject]@{ Name = $Name; Status = 'PASS'; Log = $logName; Reason = '' }
  } catch {
    $script:steps += [pscustomobject]@{ Name = $Name; Status = 'FAIL'; Log = $logName; Reason = $_.Exception.Message }
    $script:failed = $true
    "Step failed: $Name" | Tee-Object -FilePath $logPath -Append
    (($_ | Out-String).TrimEnd()) | Tee-Object -FilePath $logPath -Append
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

  $logName = Convert-ToStepLogFileName -Name $Name
  $logPath = Join-Path $script:artifactDir $logName
  "=== $Name (SKIPPED) ===" | Tee-Object -FilePath $logPath
  $Reason | Tee-Object -FilePath $logPath -Append
  $script:steps += [pscustomobject]@{ Name = $Name; Status = 'SKIP'; Log = $logName; Reason = $Reason }
}

function Get-GitHeadCommit {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $gitOutput = @(& git -C $RootPath rev-parse HEAD 2>$null)
  $gitExitCode = $LASTEXITCODE
  if ($gitExitCode -ne 0) {
    throw 'Unable to resolve git HEAD commit hash.'
  }
  $head = $gitOutput | Select-Object -First 1
  $commit = [string]$head
  if ([string]::IsNullOrWhiteSpace($commit)) {
    throw 'Resolved git HEAD commit hash is empty.'
  }
  return $commit.Trim()
}

function Get-RepoMigrationHead {
  param([Parameter(Mandatory = $true)][string]$MigrationsDirectory)

  if (-not (Test-Path $MigrationsDirectory)) {
    throw "Migration directory not found: $MigrationsDirectory"
  }

  $head = 0
  Get-ChildItem -Path $MigrationsDirectory -File -Filter '*.sql' | ForEach-Object {
    $prefix = $_.BaseName.Split('_')[0]
    $version = 0
    if ([int]::TryParse($prefix, [ref]$version) -and $version -gt $head) {
      $head = $version
    }
  }
  return $head
}

function Get-StagingDatabaseUrlFromEnvironment {
  $preferred = [string]$env:HAILO_STAGING_DATABASE_URL
  if (-not [string]::IsNullOrWhiteSpace($preferred)) {
    return $preferred.Trim()
  }
  return ([string]$env:DATABASE_URL).Trim()
}

function Normalize-StagingDatabaseUrlForProbe {
  param([Parameter(Mandatory = $true)][string]$DatabaseUrl)

  $trimmed = $DatabaseUrl.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return [pscustomobject]@{
      Url = ''
      SslMode = 'missing'
    }
  }

  try {
    $builder = [System.UriBuilder]::new($trimmed)
    $rawQuery = [string]$builder.Query
    $query = $rawQuery.TrimStart('?')
    $pairs = @()
    if (-not [string]::IsNullOrWhiteSpace($query)) {
      $pairs = @($query -split '&' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $hasSslMode = $false
    foreach ($pair in $pairs) {
      $key = (($pair -split '=', 2)[0]).Trim()
      if ([System.Uri]::UnescapeDataString($key).Equals('sslmode', [System.StringComparison]::OrdinalIgnoreCase)) {
        $hasSslMode = $true
        break
      }
    }

    if ($hasSslMode) {
      return [pscustomobject]@{
        Url = $trimmed
        SslMode = 'present'
      }
    }

    if ($pairs.Count -eq 0) {
      $builder.Query = 'sslmode=require'
    } else {
      $pairs += 'sslmode=require'
      $builder.Query = ($pairs -join '&')
    }

    return [pscustomobject]@{
      Url = $builder.Uri.AbsoluteUri
      SslMode = 'added'
    }
  } catch {
    if ($trimmed -match '(?i)(^|[?&])sslmode=') {
      return [pscustomobject]@{
        Url = $trimmed
        SslMode = 'present'
      }
    }

    $separator = if ($trimmed.Contains('?')) {
      if ($trimmed.EndsWith('?') -or $trimmed.EndsWith('&')) { '' } else { '&' }
    } else {
      '?'
    }
    return [pscustomobject]@{
      Url = "$trimmed${separator}sslmode=require"
      SslMode = 'added'
    }
  }
}

function Ensure-BackendPubGet {
  param([Parameter(Mandatory = $true)][string]$RootPath)

  $backendDir = Join-Path $RootPath 'backend'
  if (-not (Test-Path $backendDir)) {
    throw "Backend directory not found: $backendDir"
  }

  Push-Location $backendDir
  try {
    $out = & dart pub get 2>&1
    if ($LASTEXITCODE -ne 0) {
      $txt = ($out -join [Environment]::NewLine)
      throw "backend dart pub get failed with exit code $LASTEXITCODE.`n$txt"
    }
  } finally {
    Pop-Location
  }
}

function Resolve-DartExePath {
  try {
    $cmd = Get-Command dart -ErrorAction Stop
    $src = [string]$cmd.Source

    # If this is dart.bat, prefer dart.exe sitting alongside it.
    if ($src.ToLowerInvariant().EndsWith('.bat')) {
      $dir = Split-Path -Parent $src
      $exe = Join-Path $dir 'dart.exe'
      if (Test-Path $exe) {
        return $exe
      }
    }

    return $src
  } catch {
    # Fall back to "dart" if command resolution fails.
    return 'dart'
  }
}

function Invoke-DartRunCaptured {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath
  )

  $dartExe = Resolve-DartExePath
  if ([string]::IsNullOrWhiteSpace($dartExe)) {
    $dartExe = 'dart'
  }

  # Use cmd.exe to guarantee stderr+stdout capture reliably on Windows.
  $quotedDart = '"' + $dartExe.Replace('"', '""') + '"'
  $quotedScript = '"' + $ScriptPath.Replace('"', '""') + '"'
  $cmdLine = "$quotedDart run $quotedScript 2>&1"

  $output = & cmd.exe /c $cmdLine
  $exitCode = $LASTEXITCODE

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output = @($output)
    DartExe = $dartExe
    CmdLine = $cmdLine
  }
}

function Get-DatabaseMigrationHead {
  param(
    [Parameter(Mandatory = $true)][string]$RootPath,
    [string]$DatabaseUrl,
    [Parameter(Mandatory = $true)][string]$Schema
  )

  if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw 'Missing staging DB URL in this session. Set HAILO_STAGING_DATABASE_URL (preferred) or DATABASE_URL before running the gate.'
  }

  $probePath = Join-Path $RootPath 'backend/tool/get_applied_migration_head.dart'
  if (-not (Test-Path $probePath)) {
    throw "Migration head probe file not found: $probePath"
  }

  $previousDatabaseUrl = [string]$env:DATABASE_URL
  $previousSchema = [string]$env:DB_SCHEMA
  $probeOutput = @()

  try {
    $env:DATABASE_URL = $DatabaseUrl.Trim()
    $env:DB_SCHEMA = $Schema

    $result = Invoke-DartRunCaptured -ScriptPath $probePath
    $probeOutput = $result.Output

    if ($result.ExitCode -ne 0) {
      $outText = ($probeOutput -join [Environment]::NewLine)
      throw "Migration head probe failed with exit code $($result.ExitCode).`nDartExe=$($result.DartExe)`nCmd=$($result.CmdLine)`n$outText"
    }
  } finally {
    if ([string]::IsNullOrWhiteSpace($previousDatabaseUrl)) {
      Remove-Item Env:DATABASE_URL -ErrorAction SilentlyContinue
    } else {
      $env:DATABASE_URL = $previousDatabaseUrl
    }
    if ([string]::IsNullOrWhiteSpace($previousSchema)) {
      Remove-Item Env:DB_SCHEMA -ErrorAction SilentlyContinue
    } else {
      $env:DB_SCHEMA = $previousSchema
    }
  }

  $outputText = ($probeOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
  $integerMatches = [regex]::Matches($outputText, '\b\d+\b')
  if ($integerMatches.Count -lt 1) {
    throw "Unable to parse migration head probe output as an integer.`n$outputText"
  }

  $headToken = $integerMatches[$integerMatches.Count - 1].Value
  $headValue = 0
  if (-not [int]::TryParse($headToken, [ref]$headValue)) {
    throw "Unable to parse migration head probe output as an integer.`n$outputText"
  }
  return $headValue
}

function Get-HealthPayload {
  param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ArtifactFilePath,
    [string]$ExpectedCommit = '',
    [string]$ExpectedSchema = ''
  )

  $headerPath = [System.IO.Path]::GetTempFileName()
  $bodyPath = [System.IO.Path]::GetTempFileName()
  try {
    & curl.exe -sS -D $headerPath -o $bodyPath "$BaseUrl/health"
    if ($LASTEXITCODE -ne 0) {
      throw "curl failed with exit code $LASTEXITCODE for $BaseUrl/health"
    }

    $statusLine = (Get-Content $headerPath | Where-Object { $_ -match '^HTTP/\S+\s+\d{3}' } | Select-Object -Last 1)
    if (-not $statusLine) {
      throw "Unable to parse HTTP status for $BaseUrl/health"
    }
    $statusMatch = [regex]::Match($statusLine, '\s(\d{3})\b')
    if (-not $statusMatch.Success) {
      throw "Unable to parse numeric HTTP status from: $statusLine"
    }
    $status = [int]$statusMatch.Groups[1].Value
    $rawBody = Get-Content $bodyPath -Raw

    if ($status -ne 200) {
      throw "/health returned HTTP $status from $BaseUrl. Body: $rawBody"
    }

    [System.IO.File]::WriteAllText($ArtifactFilePath, $rawBody, [System.Text.Encoding]::UTF8)
    $health = $rawBody | ConvertFrom-Json

    if (-not [bool]$health.ok) {
      throw "/health did not return ok=true for $BaseUrl"
    }
    if (-not [bool]$health.db_ok) {
      throw "/health did not return db_ok=true for $BaseUrl"
    }
    if ($null -eq $health.build) {
      throw "/health payload from $BaseUrl is missing build object."
    }

    $commit = [string]$health.build.commit
    if ([string]::IsNullOrWhiteSpace($commit)) {
      throw "/health build.commit is empty for $BaseUrl"
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedCommit) -and $commit -ne $ExpectedCommit) {
      throw "/health build.commit mismatch for $BaseUrl. expected=$ExpectedCommit actual=$commit"
    }

    $schema = [string]$health.build.db_schema
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSchema) -and $schema -ne $ExpectedSchema) {
      throw "/health build.db_schema mismatch for $BaseUrl. expected=$ExpectedSchema actual=$schema"
    }

    return $health
  } finally {
    if (Test-Path $headerPath) { Remove-Item $headerPath -Force }
    if (Test-Path $bodyPath) { Remove-Item $bodyPath -Force }
  }
}

$gitHead = Get-GitHeadCommit -RootPath $root
$commitOverride = [string]$env:HAILO_EXPECTED_STAGING_COMMIT
$effectiveExpectedCommit = if (-not [string]::IsNullOrWhiteSpace($ExpectedStagingCommit)) {
  $ExpectedStagingCommit.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($commitOverride)) {
  $commitOverride.Trim()
} else {
  $gitHead
}

$context = [ordered]@{
  generated_at = (Get-Date).ToString('o')
  root = $root
  script_root = $PSScriptRoot
  git_head = $gitHead
  expected_staging_commit = $effectiveExpectedCommit
  expected_staging_schema = $ExpectedStagingSchema
}
$context | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $artifactDir 'release_gate_context.json') -Encoding UTF8

Write-Output "release_gate_root=$root"
Write-Output "release_gate_script_root=$PSScriptRoot"
Write-Output "release_gate_git_head=$gitHead"
Write-Output "release_gate_artifacts=$artifactDir"

$fatalError = $null
Push-Location $root
try {
  Invoke-GateStep -Name 'Git state cleanliness' -StopOnFail -Action {
    if ($env:HAILO_ALLOW_DIRTY -eq '1') {
      Write-Output 'Skipping clean-worktree requirement because HAILO_ALLOW_DIRTY=1'
      return
    }
    $statusLines = & git -C $root status --porcelain
    if ($LASTEXITCODE -ne 0) {
      throw "git status failed with exit code $LASTEXITCODE"
    }
    if ($statusLines) {
      $summary = ($statusLines | Select-Object -First 20) -join [Environment]::NewLine
      throw "Working tree is dirty. Commit or stash changes, or set HAILO_ALLOW_DIRTY=1.`n$summary"
    }
    Write-Output 'git status --porcelain is clean.'
  }

  Invoke-GateStep -Name 'Toolchain version drift info (non-blocking)' -Action {
    $dartVersion = ''
    $flutterVersion = ''

    try {
      $dartOutput = & dart --version 2>&1
      if ($LASTEXITCODE -eq 0) {
        $dartVersion = ($dartOutput -join ' ').Trim()
      } else {
        $dartVersion = "ERROR(exit=$LASTEXITCODE): $($dartOutput -join ' ')"
      }
    } catch {
      $dartVersion = "ERROR: $($_.Exception.Message)"
    }

    try {
      $flutterOutput = & flutter --version 2>&1
      if ($LASTEXITCODE -eq 0) {
        $flutterVersion = ($flutterOutput -join [Environment]::NewLine).Trim()
      } else {
        $flutterVersion = "ERROR(exit=$LASTEXITCODE): $($flutterOutput -join ' ')"
      }
    } catch {
      $flutterVersion = "ERROR: $($_.Exception.Message)"
    }

    $toolchainFile = Join-Path $artifactDir 'toolchain_versions.txt'
    @(
      "dart --version:"
      $dartVersion
      ''
      "flutter --version:"
      $flutterVersion
    ) | Set-Content -Path $toolchainFile -Encoding UTF8

    Write-Output "dart_version=$dartVersion"
    Write-Output "flutter_version_file=$toolchainFile"
  }

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

  Invoke-GateStep -Name 'Staging commit + schema parity' -StopOnFail -Action {
    $stagingHealthPath = Join-Path $artifactDir 'health_staging.json'
    $stagingHealth = Get-HealthPayload `
      -BaseUrl 'https://hail-o-api-staging.onrender.com' `
      -ArtifactFilePath $stagingHealthPath `
      -ExpectedCommit $effectiveExpectedCommit `
      -ExpectedSchema $ExpectedStagingSchema

    Write-Output "staging_health_artifact=$stagingHealthPath"
    Write-Output "staging_commit=$([string]$stagingHealth.build.commit)"
    Write-Output "staging_db_schema=$([string]$stagingHealth.build.db_schema)"
    Write-Output "staging_migration_head=$([string]$stagingHealth.build.migration_head)"
  }

  Invoke-GateStep -Name 'Staging DB URL presence' -StopOnFail -Action {
    $derivedUrl = Get-StagingDatabaseUrlFromEnvironment
    if ([string]::IsNullOrWhiteSpace($derivedUrl)) {
      throw 'Missing staging DB URL in this session. Set HAILO_STAGING_DATABASE_URL (preferred) or DATABASE_URL before running the gate.'
    }

    $normalized = Normalize-StagingDatabaseUrlForProbe -DatabaseUrl $derivedUrl
    $script:stagingDatabaseUrlForProbe = [string]$normalized.Url
    $script:stagingDatabaseUrlSslmode = [string]$normalized.SslMode

    $prefixLength = [Math]::Min(10, $derivedUrl.Length)
    $prefix = $derivedUrl.Substring(0, $prefixLength)
    Write-Output 'staging_db_url_present=true'
    Write-Output "staging_db_url_preview=${prefix}***"
    Write-Output "staging_db_url_sslmode=$script:stagingDatabaseUrlSslmode"
  }

  Invoke-GateStep -Name 'Migration head parity (repo vs staging db)' -StopOnFail -Action {
    Ensure-BackendPubGet -RootPath $root

    $repoHead = Get-RepoMigrationHead -MigrationsDirectory (Join-Path $root 'backend/migrations')
    if ([string]::IsNullOrWhiteSpace($script:stagingDatabaseUrlForProbe)) {
      throw 'Missing staging DB URL in this session. Set HAILO_STAGING_DATABASE_URL (preferred) or DATABASE_URL before running the gate.'
    }

    $stagingDatabaseUrl = Get-StagingDatabaseUrlFromEnvironment
    if ([string]::IsNullOrWhiteSpace($stagingDatabaseUrl)) {
      throw 'Missing staging DB URL in this session. Set HAILO_STAGING_DATABASE_URL (preferred) or DATABASE_URL before running the gate.'
    }

    $databaseUri = $null
    try {
      $databaseUri = [System.Uri]::new($stagingDatabaseUrl)
    } catch {
      throw 'Unable to parse staging DB URL for migration parity diagnostics.'
    }

    $databasePathSegments = @(
      $databaseUri.AbsolutePath.Trim('/') -split '/' |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $databaseName = ''
    if ($databasePathSegments.Count -gt 0) {
      $databaseName = [string]$databasePathSegments[$databasePathSegments.Count - 1]
    }

    Write-Output "db_host=$($databaseUri.Host)"
    Write-Output "db_name=$databaseName"
    Write-Output "db_schema=$ExpectedStagingSchema"

    $dbHead = Get-DatabaseMigrationHead `
      -RootPath $root `
      -DatabaseUrl $script:stagingDatabaseUrlForProbe `
      -Schema $ExpectedStagingSchema

    $parityPayload = [ordered]@{
      schema = $ExpectedStagingSchema
      repo_migration_head = $repoHead
      db_applied_migration_head = $dbHead
    }
    $parityPath = Join-Path $artifactDir 'migration_head_parity.json'
    $parityPayload | ConvertTo-Json -Depth 5 | Set-Content -Path $parityPath -Encoding UTF8

    Write-Output "migration_parity_artifact=$parityPath"
    Write-Output "repo_migration_head=$repoHead"
    Write-Output "db_applied_migration_head=$dbHead"
    if ($repoHead -ne $dbHead) {
      throw "Migration head mismatch for schema '$ExpectedStagingSchema': repo=$repoHead db=$dbHead"
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

  Invoke-GateStep -Name 'Backend checks (pub get + analyze + test + contract)' -StopOnFail -Action {
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

  Invoke-GateStep -Name 'Flutter tests (flutter test)' -StopOnFail -Action {
    Push-Location $root
    try {
      Write-Output "=== Flutter warmup ==="

      # Ensure flutter exists
      $flutterVersion = & flutter --version 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "flutter --version failed with exit code $LASTEXITCODE"
      }

      # Pre-cache artifacts (prevents bootstrap during test)
      & flutter precache --no-android --no-ios --no-linux --no-macos --no-windows 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "flutter precache failed with exit code $LASTEXITCODE"
      }

      # Doctor once to finish initialization
      & flutter doctor -v 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "flutter doctor failed with exit code $LASTEXITCODE"
      }

      Write-Output "=== Flutter tests ==="
      & flutter test
      if ($LASTEXITCODE -ne 0) {
        throw "flutter test failed with exit code $LASTEXITCODE"
      }
    }
    finally {
      Pop-Location
    }
  }

  Invoke-GateStep -Name 'Staging smoke (PowerShell)' -StopOnFail -Action {
    $stagingSmokeArtifactDir = Join-Path $artifactDir 'smoke_staging'
    New-Item -ItemType Directory -Path $stagingSmokeArtifactDir -Force | Out-Null
    $env:HAILO_API_BASE_URL = 'https://hail-o-api-staging.onrender.com'
    $env:ENV = 'staging'
    $env:HAILO_SMOKE_ARTIFACT_DIR = $stagingSmokeArtifactDir
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "staging smoke failed with exit code $LASTEXITCODE"
    }
  }

  Invoke-GateStep -Name 'Staging load smoke (PowerShell)' -StopOnFail -Action {
    $loadSmokeArtifactDir = Join-Path $artifactDir 'load_smoke'
    New-Item -ItemType Directory -Path $loadSmokeArtifactDir -Force | Out-Null
    $env:HAILO_API_BASE_URL = 'https://hail-o-api-staging.onrender.com'
    $env:ENV = 'staging'
    $env:HAILO_LOAD_SMOKE_ARTIFACT_DIR = $loadSmokeArtifactDir
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'load_smoke.ps1')
    if ($LASTEXITCODE -ne 0) {
      throw "staging load smoke failed with exit code $LASTEXITCODE"
    }
  }

  if ($env:HAILO_ENFORCE_RATE_LIMIT_BURST -eq '1') {
    Invoke-GateStep -Name 'Load smoke burst enforcement' -StopOnFail -Action {
      $summaryPath = Join-Path $artifactDir 'load_smoke/load_smoke_summary.json'
      if (-not (Test-Path $summaryPath)) {
        throw "Load smoke summary not found: $summaryPath"
      }
      $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
      $burst429Count = [int]$summary.burst_429_count
      Write-Output "burst_429_count=$burst429Count"
      if ($burst429Count -lt 1) {
        throw "Expected at least one 429 when HAILO_ENFORCE_RATE_LIMIT_BURST=1, got $burst429Count"
      }
    }
  } else {
    Add-SkippedStep -Name 'Load smoke burst enforcement' -Reason 'Set HAILO_ENFORCE_RATE_LIMIT_BURST=1 to require at least one 429 from load burst.'
  }

  $prodSmokeOptIn = $requestedProdSmoke -eq '1'
  $prodSmokeConfirmed = $requestedProdConfirm -eq 'I_UNDERSTAND'
  if ($prodSmokeOptIn -and $prodSmokeConfirmed) {
    Invoke-GateStep -Name 'Production smoke (PowerShell)' -StopOnFail -Action {
      $expectedProdSchema = [string]$env:HAILO_EXPECTED_PROD_SCHEMA
      $prodHealthPath = Join-Path $artifactDir 'health_prod.json'
      $prodHealth = Get-HealthPayload `
        -BaseUrl 'https://hail-o-api.onrender.com' `
        -ArtifactFilePath $prodHealthPath `
        -ExpectedSchema $expectedProdSchema
      Write-Output "prod_health_artifact=$prodHealthPath"
      Write-Output "prod_commit=$([string]$prodHealth.build.commit)"
      Write-Output "prod_db_schema=$([string]$prodHealth.build.db_schema)"

      $prodSmokeArtifactDir = Join-Path $artifactDir 'smoke_prod'
      New-Item -ItemType Directory -Path $prodSmokeArtifactDir -Force | Out-Null
      $env:HAILO_API_BASE_URL = 'https://hail-o-api.onrender.com'
      $env:ENV = 'production'
      $env:HAILO_ALLOW_PROD_SMOKE = '1'
      $env:HAILO_PROD_CONFIRM = 'I_UNDERSTAND'
      $env:HAILO_SMOKE_ARTIFACT_DIR = $prodSmokeArtifactDir
      powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'smoke_backend.ps1')
      if ($LASTEXITCODE -ne 0) {
        throw "production smoke failed with exit code $LASTEXITCODE"
      }
    }
  } else {
    $reason = 'Production smoke skipped: requires HAILO_ALLOW_PROD_SMOKE=1 and HAILO_PROD_CONFIRM=I_UNDERSTAND.'
    Add-SkippedStep -Name 'Production smoke (PowerShell)' -Reason $reason
  }
} catch {
  $fatalError = $_
  $failed = $true
} finally {
  Pop-Location
}

$summaryPath = Join-Path $artifactDir 'release_gate_summary.json'
([ordered]@{
    generated_at = (Get-Date).ToString('o')
    failed = $failed
    root = $root
    script_root = $PSScriptRoot
    git_head = $gitHead
    artifact_dir = $artifactDir
    steps = $steps
  } | ConvertTo-Json -Depth 8) | Set-Content -Path $summaryPath -Encoding UTF8

Write-Output "`n=== Release Gate Summary ==="
foreach ($step in $steps) {
  Write-Output ("{0,-45} {1,-5} {2}" -f $step.Name, $step.Status, $step.Log)
}
Write-Output "summary_artifact=$summaryPath"
Write-Output "artifact_dir=$artifactDir"

if ($null -ne $fatalError) {
  Write-Output "gate_stopped_after_failure=$($fatalError.Exception.Message)"
}

if ($failed) {
  Write-Output 'RELEASE GATE: FAIL'
  exit 1
}

Write-Output 'RELEASE GATE: PASS'
exit 0
