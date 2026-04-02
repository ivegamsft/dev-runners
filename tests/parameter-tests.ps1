<#
.SYNOPSIS
  Parameter cleanup tests — validates no hardcoded org-specific values in tracked files.

.DESCRIPTION
  Positive tests confirm sample files exist with placeholder values.
  Negative tests confirm tracked files contain no org-specific secrets.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/parameter-tests.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$pass = 0
$fail = 0

function Assert-Test {
  param([string]$Name, [bool]$Condition, [string]$FailMessage)
  if ($Condition) {
    Write-Host "  PASS: $Name" -ForegroundColor Green
    $script:pass++
  } else {
    Write-Host "  FAIL: $Name — $FailMessage" -ForegroundColor Red
    $script:fail++
  }
}

# ─── Sample files exist ──────────────────────────────────────────────────────
Write-Host "`n=== Sample files exist ===" -ForegroundColor Cyan

$sampleFiles = @(
  'env\sample.json',
  'infra\base\parameters.sample.json',
  'infra\images\parameters.sample.json',
  'infra\deploy\parameters.sample.json'
)
foreach ($f in $sampleFiles) {
  Assert-Test `
    "$f exists" `
    (Test-Path (Join-Path $repoRoot $f)) `
    "Sample file not found: $f"
}

# ─── Sample files are valid JSON ─────────────────────────────────────────────
Write-Host "`n=== Sample files are valid JSON ===" -ForegroundColor Cyan

foreach ($f in $sampleFiles) {
  $path = Join-Path $repoRoot $f
  $valid = $false
  if (Test-Path $path) {
    try { $null = Get-Content $path -Raw | ConvertFrom-Json; $valid = $true } catch { }
  }
  Assert-Test `
    "$f is valid JSON" `
    $valid `
    "Could not parse $f as JSON"
}

# ─── Sample files use placeholder values (not real org data) ─────────────────
Write-Host "`n=== Sample files use placeholders ===" -ForegroundColor Cyan

$envSample = Get-Content (Join-Path $repoRoot 'env\sample.json') -Raw
$baseSample = Get-Content (Join-Path $repoRoot 'infra\base\parameters.sample.json') -Raw
$imagesSample = Get-Content (Join-Path $repoRoot 'infra\images\parameters.sample.json') -Raw
$deploySample = Get-Content (Join-Path $repoRoot 'infra\deploy\parameters.sample.json') -Raw

# Positive: sample files contain angle-bracket placeholders
foreach ($item in @(
  @{name='env/sample.json'; content=$envSample},
  @{name='infra/base/parameters.sample.json'; content=$baseSample},
  @{name='infra/images/parameters.sample.json'; content=$imagesSample},
  @{name='infra/deploy/parameters.sample.json'; content=$deploySample}
)) {
  Assert-Test `
    "$($item.name) uses <placeholder> values" `
    ($item.content -match '<[a-z]') `
    "$($item.name) has no placeholder values"
}

# Negative: sample files do NOT contain real org-specific values
$orgPatterns = @('acme', 'a1b2', 'swedencentral', 'galacmedev', 'ssh-rsa AAAA', 'rg-acme')
foreach ($item in @(
  @{name='env/sample.json'; content=$envSample},
  @{name='infra/base/parameters.sample.json'; content=$baseSample},
  @{name='infra/images/parameters.sample.json'; content=$imagesSample},
  @{name='infra/deploy/parameters.sample.json'; content=$deploySample}
)) {
  foreach ($pat in $orgPatterns) {
    Assert-Test `
      "$($item.name) has no hardcoded '$pat'" `
      (-not ($item.content -match [regex]::Escape($pat))) `
      "$($item.name) contains hardcoded value: $pat"
  }
}

# ─── Gitignore covers local param files ──────────────────────────────────────
Write-Host "`n=== .gitignore covers local files ===" -ForegroundColor Cyan

$gitignore = Get-Content (Join-Path $repoRoot '.gitignore') -Raw

$gitignorePatterns = @('env/dev.json', 'parameters.dev.json', 'parameters.local.json')
foreach ($pat in $gitignorePatterns) {
  Assert-Test `
    ".gitignore covers $pat" `
    ($gitignore -match [regex]::Escape($pat)) `
    ".gitignore missing pattern for $pat"
}

# ─── Workflows generate env config from GitHub Variables ─────────────────────
Write-Host "`n=== Workflows use GitHub Variables fallback ===" -ForegroundColor Cyan

$workflows = @(
  @{name='build-images'; file='.github\workflows\build-images.yml'},
  @{name='deploy-base'; file='.github\workflows\deploy-base.yml'},
  @{name='deploy-from-gallery'; file='.github\workflows\deploy-from-gallery.yml'},
  @{name='rotate-secrets'; file='.github\workflows\rotate-secrets.yml'}
)
foreach ($wf in $workflows) {
  $content = Get-Content (Join-Path $repoRoot $wf.file) -Raw

  # Positive: workflow checks if env/dev.json exists before generating
  Assert-Test `
    "$($wf.name).yml checks for missing env/dev.json" `
    ($content -match 'if \[ ! -f env/dev\.json \]') `
    "$($wf.name).yml does not check for missing env/dev.json"

  # Positive: workflow references vars.ORG (GitHub Variables)
  Assert-Test `
    "$($wf.name).yml uses vars.ORG" `
    ($content -match '\$\{\{ vars\.ORG \}\}') `
    "$($wf.name).yml does not reference GitHub Variables"
}

# ─── Scripts default to parameters.local.json ────────────────────────────────
Write-Host "`n=== Scripts default to local param files ===" -ForegroundColor Cyan

$deployBasePs1   = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-base.ps1') -Raw
$deployImagesPs1 = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-images.ps1') -Raw
$setAdminPw      = Get-Content (Join-Path $repoRoot 'scripts\identity\set-admin-password.ps1') -Raw

foreach ($item in @(
  @{name='deploy-base.ps1'; content=$deployBasePs1},
  @{name='deploy-images.ps1'; content=$deployImagesPs1},
  @{name='set-admin-password.ps1'; content=$setAdminPw}
)) {
  Assert-Test `
    "$($item.name) defaults to parameters.local.json" `
    ($item.content -match 'parameters\.local\.json') `
    "$($item.name) does not default to parameters.local.json"

  # Negative: script does NOT default to parameters.dev.json
  Assert-Test `
    "$($item.name) does NOT default to parameters.dev.json" `
    (-not ($item.content -match "Default.*parameters\.dev\.json|= '.*parameters\.dev\.json'")) `
    "$($item.name) still defaults to parameters.dev.json"
}

# ─── No tracked files contain real SSH keys ──────────────────────────────────
Write-Host "`n=== No secrets in tracked files ===" -ForegroundColor Cyan

# Check all tracked .json files for real SSH keys
$trackedJson = & git -C $repoRoot ls-files '*.json' 2>$null
$sshKeyFound = $false
foreach ($f in $trackedJson) {
  if ($f) {
    $content = Get-Content (Join-Path $repoRoot $f) -Raw -ErrorAction SilentlyContinue
    if ($content -and $content -match 'ssh-rsa AAAAB3') {
      $sshKeyFound = $true
      Write-Host "    Found real SSH key in tracked file: $f" -ForegroundColor Yellow
    }
  }
}
Assert-Test `
  'No tracked JSON files contain real SSH keys' `
  (-not $sshKeyFound) `
  'Found real SSH key material in tracked files'

# ─── CAF naming compliance ────────────────────────────────────────────────────
Write-Host "`n=== CAF naming standards ===" -ForegroundColor Cyan

$mainBicep = Get-Content (Join-Path $repoRoot 'infra\base\main.bicep') -Raw

# Positive: Subnet uses snet- prefix
Assert-Test `
  'Subnet variable uses snet- prefix (CAF)' `
  ($mainBicep -match "subnetAgentsName\s*=\s*'snet-") `
  'Subnet name does not follow CAF snet- prefix convention'

# Positive: env/sample.json uses caf-region-abbrev
$envSample = Get-Content (Join-Path $repoRoot 'env\sample.json') -Raw
Assert-Test `
  'env/sample.json references caf-region-abbrev' `
  ($envSample -match 'caf-region-abbrev') `
  'env/sample.json does not reference CAF region abbreviation'

# Positive: Bicep env param has default value
Assert-Test `
  'Bicep env parameter has default value' `
  ($mainBicep -match "param\s+env\s+string\s*=\s*'dev'") `
  'Bicep env parameter missing default value'

# Positive: Bicep adminUsername param has default value
Assert-Test `
  'Bicep adminUsername has default value' `
  ($mainBicep -match "param\s+adminUsername\s+string\s*=\s*'azureadmin'") `
  'Bicep adminUsername parameter missing default value'

# Positive: Bootstrap has CAF region map
$bootstrap = Get-Content (Join-Path $repoRoot 'scripts\bootstrap.ps1') -Raw
Assert-Test `
  'Bootstrap has CAF region abbreviation map' `
  ($bootstrap -match 'eastus2.*eus2|eus2.*eastus2') `
  'Bootstrap missing CAF region abbreviation map'

# Positive: Bootstrap has only 4 mandatory params
Assert-Test `
  'Bootstrap Org is mandatory' `
  ($bootstrap -match '\[Parameter\(Mandatory[^]]*\]\s*\[string\]\s*\$Org') `
  'Org should be mandatory in bootstrap'

Assert-Test `
  'Bootstrap SubscriptionId is mandatory' `
  ($bootstrap -match '\[Parameter\(Mandatory[^]]*\]\s*\[string\]\s*\$SubscriptionId') `
  'SubscriptionId should be mandatory in bootstrap'

Assert-Test `
  'Bootstrap Env has default value' `
  ($bootstrap -match "\[string\]\s*\`$Env\s*=\s*'dev'") `
  'Env should have a default value in bootstrap'

# Positive: GETTING_STARTED.md uses generic examples
$gettingStarted = Get-Content (Join-Path $repoRoot 'docs\GETTING_STARTED.md') -Raw
Assert-Test `
  'GETTING_STARTED uses myorg examples (not acme)' `
  ($gettingStarted -notmatch '\bacme\b') `
  'GETTING_STARTED.md still references acme'

# Positive: base parameters.sample.json has defaults for env and adminUsername
$baseSample = Get-Content (Join-Path $repoRoot 'infra\base\parameters.sample.json') -Raw | ConvertFrom-Json
Assert-Test `
  'base parameters.sample.json env defaults to dev' `
  ($baseSample.parameters.env.value -eq 'dev') `
  'base parameters.sample.json env should default to dev'

Assert-Test `
  'base parameters.sample.json adminUsername defaults to azureadmin' `
  ($baseSample.parameters.adminUsername.value -eq 'azureadmin') `
  'base parameters.sample.json adminUsername should default to azureadmin'

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Parameter Tests: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
