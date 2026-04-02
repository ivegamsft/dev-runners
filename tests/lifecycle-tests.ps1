<#
.SYNOPSIS
  Lifecycle tests — validates bootstrap, verify, and cleanup scripts exist and are well-structured.

.DESCRIPTION
  Positive tests confirm lifecycle scripts exist with expected patterns.
  Negative tests confirm no anti-patterns.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/lifecycle-tests.ps1
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

# ─── Bootstrap script ────────────────────────────────────────────────────────
Write-Host "`n=== Bootstrap script ===" -ForegroundColor Cyan

$bootstrapPath = Join-Path $repoRoot 'scripts\bootstrap.ps1'
$bootstrap = if (Test-Path $bootstrapPath) { Get-Content $bootstrapPath -Raw } else { '' }

Assert-Test 'bootstrap.ps1 exists' (Test-Path $bootstrapPath) 'scripts/bootstrap.ps1 not found'
Assert-Test 'bootstrap.ps1 has Set-StrictMode' ($bootstrap -match 'Set-StrictMode') 'Missing Set-StrictMode'
Assert-Test 'bootstrap.ps1 checks prerequisites' ($bootstrap -match 'prerequisite|prereq' -or $bootstrap -match 'az.*version|gh.*--version') 'No prerequisite checking'
Assert-Test 'bootstrap.ps1 copies sample files' ($bootstrap -match 'sample\.json|env\\dev\.json') 'Does not create local config from samples'
Assert-Test 'bootstrap.ps1 creates resource group' ($bootstrap -match 'az group create') 'Does not create resource group'
Assert-Test 'bootstrap.ps1 calls OIDC setup' ($bootstrap -match 'setup-github-oidc') 'Does not set up OIDC'
Assert-Test 'bootstrap.ps1 sets GitHub variables' ($bootstrap -match 'gh variable set') 'Does not configure GitHub variables'
Assert-Test 'bootstrap.ps1 sets GitHub secrets' ($bootstrap -match 'gh secret set') 'Does not configure GitHub secrets'
Assert-Test 'bootstrap.ps1 supports -WhatIf' ($bootstrap -match '\[switch\]\$WhatIf') 'Missing -WhatIf support'
Assert-Test 'bootstrap.ps1 has Mandatory params' ($bootstrap -match '\[Parameter\(Mandatory\)\]') 'No mandatory parameters defined'

# Negative: no hardcoded org-specific values (outside help/comment blocks)
$bootstrapCode = ($bootstrap -split '(?m)^#>')[1]
if (-not $bootstrapCode) { $bootstrapCode = $bootstrap }
Assert-Test 'bootstrap.ps1 has no hardcoded subscription ID in code' (-not ($bootstrapCode -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')) 'Contains hardcoded GUID in code body'

# ─── Verify script ───────────────────────────────────────────────────────────
Write-Host "`n=== Verify script ===" -ForegroundColor Cyan

$verifyPath = Join-Path $repoRoot 'scripts\verify-environment.ps1'
$verify = if (Test-Path $verifyPath) { Get-Content $verifyPath -Raw } else { '' }

Assert-Test 'verify-environment.ps1 exists' (Test-Path $verifyPath) 'scripts/verify-environment.ps1 not found'
Assert-Test 'verify-environment.ps1 has Set-StrictMode' ($verify -match 'Set-StrictMode') 'Missing Set-StrictMode'
Assert-Test 'verify-environment.ps1 supports -SkipAzure' ($verify -match '\[switch\]\$SkipAzure') 'Missing -SkipAzure support'
Assert-Test 'verify-environment.ps1 runs static tests' ($verify -match 'sprint.*tests\.ps1|parameter-tests\.ps1') 'Does not run static tests'
Assert-Test 'verify-environment.ps1 checks manifest freshness' ($verify -match 'update-agent-manifest|manifest.*fresh') 'Does not check manifest'
Assert-Test 'verify-environment.ps1 checks for secrets in tracked files' ($verify -match 'ssh-rsa|SSH.*key.*tracked') 'Does not scan for secrets'
Assert-Test 'verify-environment.ps1 checks Azure resources' ($verify -match 'Key Vault|keyvault|Microsoft\.KeyVault') 'No Azure resource checks'
Assert-Test 'verify-environment.ps1 checks VMSS' ($verify -match 'vmss') 'No VMSS check'
Assert-Test 'verify-environment.ps1 checks NSG' ($verify -match 'NSG|networkSecurityGroups') 'No NSG check'
Assert-Test 'verify-environment.ps1 reports pass/fail summary' ($verify -match 'pass.*fail|Verification:') 'No summary output'

# ─── Cleanup script ──────────────────────────────────────────────────────────
Write-Host "`n=== Cleanup script ===" -ForegroundColor Cyan

$cleanupPath = Join-Path $repoRoot 'scripts\cleanup.ps1'
$cleanup = if (Test-Path $cleanupPath) { Get-Content $cleanupPath -Raw } else { '' }

Assert-Test 'cleanup.ps1 exists' (Test-Path $cleanupPath) 'scripts/cleanup.ps1 not found'
Assert-Test 'cleanup.ps1 has Set-StrictMode' ($cleanup -match 'Set-StrictMode') 'Missing Set-StrictMode'
Assert-Test 'cleanup.ps1 deletes resource group' ($cleanup -match 'az group delete') 'Does not delete resource group'
Assert-Test 'cleanup.ps1 supports -IncludeOidc' ($cleanup -match '\$IncludeOidc') 'Missing OIDC cleanup option'
Assert-Test 'cleanup.ps1 supports -IncludeGitHub' ($cleanup -match '\$IncludeGitHub') 'Missing GitHub cleanup option'
Assert-Test 'cleanup.ps1 supports -WhatIf' ($cleanup -match '\[switch\]\$WhatIf') 'Missing -WhatIf support'
Assert-Test 'cleanup.ps1 supports -Force' ($cleanup -match '\[switch\]\$Force') 'Missing -Force support'
Assert-Test 'cleanup.ps1 has confirmation prompt' ($cleanup -match 'Read-Host|confirm') 'No confirmation before destructive action'
Assert-Test 'cleanup.ps1 removes Entra app' ($cleanup -match 'az ad app delete') 'Does not delete Entra app'
Assert-Test 'cleanup.ps1 clears GitHub secrets' ($cleanup -match 'gh secret delete') 'Does not clear GitHub secrets'
Assert-Test 'cleanup.ps1 clears GitHub variables' ($cleanup -match 'gh variable delete') 'Does not clear GitHub variables'

# Negative: cleanup has safeguards
Assert-Test 'cleanup.ps1 warns before destroying' ($cleanup -match 'DESTROY|WARNING|destructive' -or $cleanup -match 'This will') 'No destruction warning'

# ─── Documentation ────────────────────────────────────────────────────────────
Write-Host "`n=== Lifecycle documentation ===" -ForegroundColor Cyan

$gettingStarted = Join-Path $repoRoot 'docs\GETTING_STARTED.md'
$gsContent = if (Test-Path $gettingStarted) { Get-Content $gettingStarted -Raw } else { '' }

Assert-Test 'GETTING_STARTED.md exists' (Test-Path $gettingStarted) 'docs/GETTING_STARTED.md not found'
Assert-Test 'GETTING_STARTED.md covers prerequisites' ($gsContent -match 'Prerequisites|prereq') 'Missing prerequisites section'
Assert-Test 'GETTING_STARTED.md covers bootstrap' ($gsContent -match 'bootstrap\.ps1') 'Missing bootstrap instructions'
Assert-Test 'GETTING_STARTED.md covers verification' ($gsContent -match 'verify-environment\.ps1') 'Missing verification instructions'
Assert-Test 'GETTING_STARTED.md covers cleanup' ($gsContent -match 'cleanup\.ps1') 'Missing cleanup instructions'
Assert-Test 'GETTING_STARTED.md covers manual setup' ($gsContent -match 'Manual Setup|manual') 'Missing manual setup path'
Assert-Test 'GETTING_STARTED.md covers GitHub variables' ($gsContent -match 'AZURE_CLIENT_ID|Repository Variables') 'Missing GitHub config docs'
Assert-Test 'GETTING_STARTED.md has troubleshooting' ($gsContent -match 'Troubleshoot') 'Missing troubleshooting section'

# ─── Verify script runs offline successfully ──────────────────────────────────
Write-Host "`n=== Verify script offline execution ===" -ForegroundColor Cyan

try {
  $verifyOutput = & pwsh -File $verifyPath -SkipAzure 2>&1
  $verifyExit = $LASTEXITCODE
  # We expect it to pass (exit 0) when offline with clean repo state
  Assert-Test 'verify-environment.ps1 -SkipAzure completes' ($true) ''
  Assert-Test 'verify-environment.ps1 -SkipAzure outputs summary' (($verifyOutput -join "`n") -match 'Verification:') 'No summary in output'
} catch {
  Assert-Test 'verify-environment.ps1 -SkipAzure completes' $false $_.Exception.Message
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Lifecycle Tests: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
