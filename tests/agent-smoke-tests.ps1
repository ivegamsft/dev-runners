<#
.SYNOPSIS
  Agent smoke tests — validates verify-agents.ps1 structure, env config, and docs.

.DESCRIPTION
  Static regression tests for issue #29 (post-deploy agent verification).
  Positive tests confirm expected patterns exist.
  Negative tests confirm anti-patterns are absent.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/agent-smoke-tests.ps1
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

$verifyAgentsPath = Join-Path $repoRoot 'scripts\validate\verify-agents.ps1'
$verifyAgents = if (Test-Path $verifyAgentsPath) { Get-Content $verifyAgentsPath -Raw } else { '' }

$verifyEnvPath = Join-Path $repoRoot 'scripts\verify-environment.ps1'
$verifyEnv = if (Test-Path $verifyEnvPath) { Get-Content $verifyEnvPath -Raw } else { '' }

$sampleJsonPath = Join-Path $repoRoot 'env\sample.json'
$sampleJson = if (Test-Path $sampleJsonPath) { Get-Content $sampleJsonPath -Raw } else { '' }

$gettingStartedPath = Join-Path $repoRoot 'docs\GETTING_STARTED.md'
$gettingStarted = if (Test-Path $gettingStartedPath) { Get-Content $gettingStartedPath -Raw } else { '' }

# ─── Issue #29: verify-agents.ps1 existence & structure ──────────────────────
Write-Host "`n=== Issue #29: verify-agents.ps1 ===" -ForegroundColor Cyan

Assert-Test `
  'verify-agents.ps1 exists' `
  (Test-Path $verifyAgentsPath) `
  'scripts/validate/verify-agents.ps1 not found'

Assert-Test `
  'verify-agents.ps1 has Set-StrictMode' `
  ($verifyAgents -match 'Set-StrictMode') `
  'Missing Set-StrictMode'

Assert-Test `
  'verify-agents.ps1 has ErrorActionPreference Stop' `
  ($verifyAgents -match "\`$ErrorActionPreference\s*=\s*'Stop'") `
  'Missing ErrorActionPreference Stop'

Assert-Test `
  'verify-agents.ps1 has Mandatory SubscriptionId param' `
  ($verifyAgents -match '\[Parameter\(Mandatory\)\]' -and $verifyAgents -match '\$SubscriptionId') `
  'Missing mandatory SubscriptionId parameter'

Assert-Test `
  'verify-agents.ps1 accepts AdoOrgUrl param' `
  ($verifyAgents -match '\$AdoOrgUrl') `
  'Missing AdoOrgUrl parameter'

Assert-Test `
  'verify-agents.ps1 accepts AdoPoolName param' `
  ($verifyAgents -match '\$AdoPoolName') `
  'Missing AdoPoolName parameter'

Assert-Test `
  'verify-agents.ps1 accepts GitHubRepo param' `
  ($verifyAgents -match '\$GitHubRepo') `
  'Missing GitHubRepo parameter'

Assert-Test `
  'verify-agents.ps1 accepts TimeoutSeconds param' `
  ($verifyAgents -match '\$TimeoutSeconds') `
  'Missing TimeoutSeconds parameter'

Assert-Test `
  'verify-agents.ps1 loads env config' `
  ($verifyAgents -match 'env\\dev\.json|EnvConfig') `
  'Does not load env config'

# ─── ADO agent verification logic ────────────────────────────────────────────
Write-Host "`n=== Issue #29: ADO agent verification ===" -ForegroundColor Cyan

Assert-Test `
  'verify-agents.ps1 queries ADO agent pools API' `
  ($verifyAgents -match 'distributedtask/pools') `
  'No ADO pools API call'

Assert-Test `
  'verify-agents.ps1 checks agent online status' `
  ($verifyAgents -match "status.*-eq.*'online'" -or $verifyAgents -match "'online'") `
  'No online status check'

Assert-Test `
  'verify-agents.ps1 reports agent capabilities' `
  ($verifyAgents -match 'Capabilities|Agent\.OS|Agent\.ComputerName') `
  'Does not report agent capabilities'

Assert-Test `
  'verify-agents.ps1 uses Bearer token for ADO' `
  ($verifyAgents -match 'Bearer.*adoToken|Authorization.*Bearer') `
  'Does not use Bearer auth for ADO API'

Assert-Test `
  'verify-agents.ps1 obtains token via az CLI' `
  ($verifyAgents -match 'az account get-access-token.*499b84ac') `
  'Does not obtain ADO token via az CLI (resource 499b84ac...)'

# ─── GitHub runner verification logic ────────────────────────────────────────
Write-Host "`n=== Issue #29: GitHub runner verification ===" -ForegroundColor Cyan

Assert-Test `
  'verify-agents.ps1 queries GitHub runners API' `
  ($verifyAgents -match 'actions/runners') `
  'No GitHub runners API call'

Assert-Test `
  'verify-agents.ps1 uses gh CLI for GitHub API' `
  ($verifyAgents -match 'gh api') `
  'Does not use gh CLI for GitHub API'

Assert-Test `
  'verify-agents.ps1 checks for self-hosted label' `
  ($verifyAgents -match 'self-hosted') `
  'Does not check for self-hosted label'

Assert-Test `
  'verify-agents.ps1 reports runner OS and labels' `
  ($verifyAgents -match 'runner\.os|runner.*labels' -or ($verifyAgents -match '\$runner\.os' -or $verifyAgents -match 'labels')) `
  'Does not report runner OS or labels'

# ─── Polling & timeout ────────────────────────────────────────────────────────
Write-Host "`n=== Issue #29: Polling & timeout ===" -ForegroundColor Cyan

Assert-Test `
  'verify-agents.ps1 polls with timeout' `
  ($verifyAgents -match 'deadline|TimeoutSeconds') `
  'No timeout/polling mechanism'

Assert-Test `
  'verify-agents.ps1 has configurable poll interval' `
  ($verifyAgents -match 'pollInterval|Start-Sleep') `
  'No poll interval'

Assert-Test `
  'verify-agents.ps1 has pass/fail summary' `
  ($verifyAgents -match 'pass.*fail|Agent Verification:') `
  'No summary output'

Assert-Test `
  'verify-agents.ps1 exits non-zero on failure' `
  ($verifyAgents -match 'exit.*\$fail.*-gt.*0') `
  'Does not exit non-zero on failure'

# ─── Graceful skips ──────────────────────────────────────────────────────────
Write-Host "`n=== Issue #29: Graceful skip behavior ===" -ForegroundColor Cyan

Assert-Test `
  'verify-agents.ps1 skips ADO checks when AdoOrgUrl not provided' `
  ($verifyAgents -match 'SKIP.*ADO_ORG_URL') `
  'Does not gracefully skip ADO checks'

Assert-Test `
  'verify-agents.ps1 skips GitHub checks when GitHubRepo not provided' `
  ($verifyAgents -match 'SKIP.*GITHUB_REPO') `
  'Does not gracefully skip GitHub checks'

# ─── Negative tests ──────────────────────────────────────────────────────────
Write-Host "`n=== Issue #29: Negative tests ===" -ForegroundColor Cyan

# No hardcoded secrets or tokens
$verifyAgentsCode = ($verifyAgents -split '(?m)^#>')[1]
if (-not $verifyAgentsCode) { $verifyAgentsCode = $verifyAgents }

Assert-Test `
  'verify-agents.ps1 has no hardcoded PAT or token' `
  (-not ($verifyAgentsCode -match '[A-Za-z0-9]{52}|ghp_[A-Za-z0-9]{36}')) `
  'Contains what looks like a hardcoded token'

Assert-Test `
  'verify-agents.ps1 has no hardcoded subscription ID' `
  (-not ($verifyAgentsCode -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' -and $verifyAgentsCode -notmatch '499b84ac-1321-427f-aa17-267ca6975798')) `
  'Contains hardcoded GUID (other than ADO resource ID)'

# ─── verify-environment.ps1 integration ───────────────────────────────────────
Write-Host "`n=== Issue #29: verify-environment.ps1 integration ===" -ForegroundColor Cyan

Assert-Test `
  'verify-environment.ps1 references verify-agents' `
  ($verifyEnv -match 'verify-agents') `
  'verify-environment.ps1 does not reference verify-agents.ps1'

Assert-Test `
  'verify-environment.ps1 runs agent-smoke-tests' `
  ($verifyEnv -match 'agent-smoke-tests') `
  'verify-environment.ps1 does not run agent-smoke-tests.ps1'

# ─── env/sample.json has agent verification vars ─────────────────────────────
Write-Host "`n=== Issue #29: env/sample.json ===" -ForegroundColor Cyan

Assert-Test `
  'sample.json has ADO_ORG_URL' `
  ($sampleJson -match 'ADO_ORG_URL') `
  'env/sample.json missing ADO_ORG_URL'

Assert-Test `
  'sample.json has ADO_POOL_NAME' `
  ($sampleJson -match 'ADO_POOL_NAME') `
  'env/sample.json missing ADO_POOL_NAME'

Assert-Test `
  'sample.json has GITHUB_REPO' `
  ($sampleJson -match 'GITHUB_REPO') `
  'env/sample.json missing GITHUB_REPO'

# ─── Documentation ────────────────────────────────────────────────────────────
Write-Host "`n=== Issue #29: Documentation ===" -ForegroundColor Cyan

Assert-Test `
  'GETTING_STARTED.md documents verify-agents.ps1' `
  ($gettingStarted -match 'verify-agents') `
  'docs/GETTING_STARTED.md does not mention verify-agents.ps1'

Assert-Test `
  'GETTING_STARTED.md documents agent-smoke-tests.ps1' `
  ($gettingStarted -match 'agent-smoke-tests') `
  'docs/GETTING_STARTED.md does not mention agent-smoke-tests.ps1'

Assert-Test `
  'GETTING_STARTED.md has ADO_ORG_URL in variables table' `
  ($gettingStarted -match 'ADO_ORG_URL') `
  'docs/GETTING_STARTED.md missing ADO_ORG_URL'

Assert-Test `
  'GETTING_STARTED.md has agent troubleshooting entries' `
  ($gettingStarted -match 'agent.*not.*online|runner.*not.*register|bootstrap.*5 min') `
  'docs/GETTING_STARTED.md missing agent troubleshooting'

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Agent Smoke Tests: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
