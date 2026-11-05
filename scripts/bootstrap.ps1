$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -Raw (Join-Path $repositoryRoot "package.json") |
  ConvertFrom-Json

if (
  $manifest.packageManager -notmatch
  "^pnpm@(?<version>(?<major>\d+)\.\d+\.\d+)(?:\+.+)?$"
) {
  throw "package.json must declare an exact pnpm version in packageManager."
}

$requiredPnpmVersion = $Matches.version
$requiredPnpmMajor = [int]$Matches.major
$nodeVersion = $manifest.devEngines.runtime.version
if (-not $nodeVersion) {
  throw "package.json must declare an exact Node.js version in devEngines.runtime."
}

$persistentSystemCa = @(
  [Environment]::GetEnvironmentVariable("NODE_USE_SYSTEM_CA", "User")
  [Environment]::GetEnvironmentVariable("NODE_USE_SYSTEM_CA", "Machine")
) -contains "1"
if (-not $persistentSystemCa) {
  throw @"
NODE_USE_SYSTEM_CA must be set to 1.
Set it permanently, relaunch affected terminals, IDEs, and apps, then run this script again:
[Environment]::SetEnvironmentVariable("NODE_USE_SYSTEM_CA", "1", "User")
"@
}
$env:NODE_USE_SYSTEM_CA = "1"

$wingetPnpm = winget list --exact --id pnpm.pnpm --accept-source-agreements |
  Out-String
if ($LASTEXITCODE -ne 0 -or $wingetPnpm -notmatch "\bpnpm\.pnpm\b") {
  throw @"
pnpm is required.
Install it with WinGet, relaunch affected terminals, IDEs, and apps, then run this script again:
winget install --exact --id pnpm.pnpm
"@
}
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  throw "pnpm is installed through WinGet but is not on PATH. Relaunch affected terminals, IDEs, and apps, then run this script again."
}

$previousPmOnFail = $env:PNPM_CONFIG_PM_ON_FAIL
try {
  $env:PNPM_CONFIG_PM_ON_FAIL = "ignore"
  $bootstrapPnpmVersion = pnpm --version
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine the installed pnpm version."
  }
} finally {
  if ($null -eq $previousPmOnFail) {
    Remove-Item Env:PNPM_CONFIG_PM_ON_FAIL -ErrorAction SilentlyContinue
  } else {
    $env:PNPM_CONFIG_PM_ON_FAIL = $previousPmOnFail
  }
}
if ($bootstrapPnpmVersion -notmatch "^(?<major>\d+)\.") {
  throw "Unable to parse the installed pnpm version: $bootstrapPnpmVersion."
}
if ([int]$Matches.major -ne $requiredPnpmMajor) {
  throw "pnpm major $requiredPnpmMajor is required; found $bootstrapPnpmVersion. Update pnpm with WinGet."
}

Push-Location $repositoryRoot
try {
  pnpm install --frozen-lockfile
  if ($LASTEXITCODE -ne 0) {
    throw "Workspace installation failed."
  }

  $projectPnpmVersion = pnpm --version
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine the project pnpm version."
  }
  if ($projectPnpmVersion -ne $requiredPnpmVersion) {
    throw "pnpm $requiredPnpmVersion is required; the workspace selected $projectPnpmVersion."
  }

  $installedNodeVersion = pnpm exec node --version
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine the project Node.js version."
  }
  if ($installedNodeVersion -ne "v$nodeVersion") {
    throw "Node.js $nodeVersion is required; pnpm selected $installedNodeVersion."
  }
} finally {
  Pop-Location
}
