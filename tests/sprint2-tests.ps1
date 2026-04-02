<#
.SYNOPSIS
  Sprint 2 regression tests — validates fixes for issues #11, #12, #13, #14, #15, #16.

.DESCRIPTION
  Positive tests confirm expected patterns exist.
  Negative tests confirm anti-patterns are absent.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/sprint2-tests.ps1
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

# ─── Load file contents ──────────────────────────────────────────────────────
$envConfigPath   = Join-Path $repoRoot 'env\dev.json'
$buildImagesYml  = Get-Content (Join-Path $repoRoot '.github\workflows\build-images.yml') -Raw
$deployBaseYml   = Get-Content (Join-Path $repoRoot '.github\workflows\deploy-base.yml') -Raw
$deployGalleryYml = Get-Content (Join-Path $repoRoot '.github\workflows\deploy-from-gallery.yml') -Raw
$securityInfraYml = Get-Content (Join-Path $repoRoot '.github\workflows\security-infra.yml') -Raw
$mainBicep       = Get-Content (Join-Path $repoRoot 'infra\base\main.bicep') -Raw
$paramsDev       = Get-Content (Join-Path $repoRoot 'infra\base\parameters.dev.json') -Raw
$validatePs1     = Get-Content (Join-Path $repoRoot 'scripts\validate\validate-base.ps1') -Raw
$oidcPs1         = Get-Content (Join-Path $repoRoot 'scripts\identity\setup-github-oidc.ps1') -Raw
$deployBasePs1   = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-base.ps1') -Raw
$deployImagesPs1 = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-images.ps1') -Raw

# ─── Issue #11: Centralized environment config ───────────────────────────────
Write-Host "`n=== Issue #11: Centralized environment config ===" -ForegroundColor Cyan

# Positive: env/dev.json exists and is valid JSON
Assert-Test `
  'env/dev.json exists' `
  (Test-Path $envConfigPath) `
  'env/dev.json not found'

$envConfig = $null
if (Test-Path $envConfigPath) {
  try { $envConfig = Get-Content $envConfigPath -Raw | ConvertFrom-Json } catch { }
}

Assert-Test `
  'env/dev.json is valid JSON' `
  ($null -ne $envConfig) `
  'env/dev.json could not be parsed as JSON'

# Positive: env/dev.json has required keys
$requiredKeys = @('ORG','ENV','LOCATION','LOC','UNIQUE_SUFFIX','RESOURCE_GROUP','GALLERY_NAME','ADMIN_USERNAME')
$missingKeys = @()
if ($envConfig) {
  foreach ($k in $requiredKeys) {
    if (-not ($envConfig.PSObject.Properties.Name -contains $k)) { $missingKeys += $k }
  }
}
Assert-Test `
  'env/dev.json has all required keys' `
  ($missingKeys.Count -eq 0) `
  "Missing keys: $($missingKeys -join ', ')"

# Positive: workflows load from env/dev.json (jq step exists)
foreach ($wf in @(@{name='build-images';content=$buildImagesYml}, @{name='deploy-base';content=$deployBaseYml}, @{name='deploy-from-gallery';content=$deployGalleryYml})) {
  Assert-Test `
    "$($wf.name).yml loads env/dev.json" `
    ($wf.content -match 'env/dev\.json.*GITHUB_ENV') `
    "Workflow $($wf.name) does not load from env/dev.json"
}

# Negative: workflows do NOT have hardcoded workflow-level env blocks with ORG/ENV/LOCATION
foreach ($wf in @(@{name='build-images';content=$buildImagesYml}, @{name='deploy-base';content=$deployBaseYml}, @{name='deploy-from-gallery';content=$deployGalleryYml})) {
  $headerSection = ($wf.content -split '(?m)^jobs:')[0]
  $hasHardcodedEnv = $headerSection -match '(?m)^env:\s*\n' -and $headerSection -match '(?m)^\s+ORG:'
  Assert-Test `
    "$($wf.name).yml has no hardcoded workflow-level env block" `
    (-not $hasHardcodedEnv) `
    "Workflow $($wf.name) still has hardcoded ORG in workflow-level env"
}

# Positive: scripts load from env config
Assert-Test `
  'deploy-base.ps1 loads from env config' `
  ($deployBasePs1 -match 'env.*dev\.json' -or $deployBasePs1 -match 'EnvConfig') `
  'deploy-base.ps1 does not reference env config'

Assert-Test `
  'deploy-images.ps1 loads from env config' `
  ($deployImagesPs1 -match 'env.*dev\.json' -or $deployImagesPs1 -match 'EnvConfig') `
  'deploy-images.ps1 does not reference env config'

# Negative: scripts do NOT have hardcoded subscription IDs
Assert-Test `
  'deploy-base.ps1 has no hardcoded subscription ID' `
  (-not ($deployBasePs1 -match '844eabcc')) `
  'deploy-base.ps1 still has hardcoded subscription ID'

Assert-Test `
  'deploy-images.ps1 has no hardcoded subscription ID' `
  (-not ($deployImagesPs1 -match '844eabcc')) `
  'deploy-images.ps1 still has hardcoded subscription ID'

# ─── Issue #12: Validation logic mismatch ────────────────────────────────────
Write-Host "`n=== Issue #12: Validation logic mismatch ===" -ForegroundColor Cyan

# Positive: parameters.dev.json has linuxUsePassword=false
Assert-Test `
  'parameters.dev.json has linuxUsePassword=false' `
  ($paramsDev -match '"linuxUsePassword".*"value":\s*false') `
  'linuxUsePassword is not false in parameters.dev.json'

# Positive: validator accepts configurable password auth expectation
Assert-Test `
  'Validator has ExpectLinuxPasswordAuthDisabled parameter' `
  ($validatePs1 -match '\$ExpectLinuxPasswordAuthDisabled') `
  'Validator missing ExpectLinuxPasswordAuthDisabled parameter'

# Positive: validator uses the configurable parameter in its check
Assert-Test `
  'Validator uses ExpectLinuxPasswordAuthDisabled in assertion' `
  ($validatePs1 -match 'ExpectLinuxPasswordAuthDisabled.*Assert-OrFail|Assert-OrFail.*ExpectLinuxPasswordAuthDisabled') `
  'Validator does not use ExpectLinuxPasswordAuthDisabled in checks'

# ─── Issue #13: Validator expects removed deploy identity ────────────────────
Write-Host "`n=== Issue #13: Deploy identity removed from validator ===" -ForegroundColor Cyan

# Negative: validator does NOT check for deploy identity
Assert-Test `
  'Validator does not check for deploy identity' `
  (-not ($validatePs1 -match "'deploy'")) `
  'Validator still checks for removed deploy identity'

# Positive: validator checks for the 3 actual identities
foreach ($id in 'lin-agents','win-agents','gh-runner') {
  Assert-Test `
    "Validator checks for $id identity" `
    ($validatePs1 -match [regex]::Escape("'$id'")) `
    "Validator missing check for $id identity"
}

# ─── Issue #14: Deterministic fallback admin password removed ────────────────
Write-Host "`n=== Issue #14: No deterministic fallback password ===" -ForegroundColor Cyan

# Negative: no fallbackAdminPassword variable in Bicep
Assert-Test `
  'No fallbackAdminPassword in main.bicep' `
  (-not ($mainBicep -match 'fallbackAdminPassword')) `
  'main.bicep still contains fallbackAdminPassword'

# Negative: no deterministic password segment generation
Assert-Test `
  'No deterministic pwSeg variables in main.bicep' `
  (-not ($mainBicep -match 'pwSeg[123]')) `
  'main.bicep still has pwSeg deterministic password segments'

# Positive: adminPassword has @minLength decorator
Assert-Test `
  'adminPassword has @minLength(16) enforcement' `
  ($mainBicep -match '@minLength\(16\)\s*\r?\nparam adminPassword') `
  'adminPassword missing @minLength(16) decorator'

# Negative: parameters.dev.json does NOT contain empty adminPassword
Assert-Test `
  'parameters.dev.json does not have empty adminPassword' `
  (-not ($paramsDev -match '"adminPassword"')) `
  'parameters.dev.json still has adminPassword entry (should be provided at deploy time)'

# Positive: deploy-base.yml generates password dynamically
Assert-Test `
  'deploy-base.yml has Resolve Admin Password step' `
  ($deployBaseYml -match 'Resolve Admin Password') `
  'deploy-base.yml missing dynamic password resolution'

# Positive: deploy-from-gallery.yml generates password dynamically
Assert-Test `
  'deploy-from-gallery.yml has Resolve Admin Password step' `
  ($deployGalleryYml -match 'Resolve Admin Password') `
  'deploy-from-gallery.yml missing dynamic password resolution'

# ─── Issue #15: PSScriptAnalyzer array-to-Path fix ───────────────────────────
Write-Host "`n=== Issue #15: PSScriptAnalyzer iteration fix ===" -ForegroundColor Cyan

# Positive: security-infra uses foreach iteration
Assert-Test `
  'security-infra.yml iterates scripts with foreach' `
  ($securityInfraYml -match 'foreach.*\$scriptPath') `
  'security-infra.yml does not use foreach for script iteration'

# Negative: does NOT pass array directly to -Path
Assert-Test `
  'No direct array pass to Invoke-ScriptAnalyzer -Path' `
  (-not ($securityInfraYml -match 'Invoke-ScriptAnalyzer\s+-Path\s+\$scripts\b')) `
  'Still passing array directly to -Path parameter'

# ─── Issue #16: Identity setup script ambiguity ──────────────────────────────
Write-Host "`n=== Issue #16: Identity setup script handles ambiguity ===" -ForegroundColor Cyan

# Negative: no [0] query in app lookup
Assert-Test `
  'setup-github-oidc.ps1 does not use [0] query for app lookup' `
  (-not ($oidcPs1 -match "az ad app list.*\[0\]")) `
  'Script still uses [0] to silently pick first app'

# Positive: script checks for multiple matches
Assert-Test `
  'Script checks for multiple app matches' `
  ($oidcPs1 -match '\.Count\s*-gt\s*1') `
  'Script does not check for multiple matching apps'

# Positive: script throws on ambiguous match
Assert-Test `
  'Script throws error on ambiguous match' `
  ($oidcPs1 -match 'throw.*[Aa]mbiguous') `
  'Script does not throw on ambiguous app match'

# Positive: script still handles zero matches (create new)
Assert-Test `
  'Script still creates app when no match found' `
  ($oidcPs1 -match 'az ad app create') `
  'Script lost the create-new-app path'

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Sprint 2 Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
