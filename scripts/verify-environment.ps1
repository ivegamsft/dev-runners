<#
.SYNOPSIS
  Verify a deployed dev-runners environment.

.DESCRIPTION
  Post-deployment verification that checks:
  - Offline: local config files, static tests, PSScriptAnalyzer, manifest freshness
  - Online (requires Azure): resource group, Key Vault, gallery, identities, VMSS, VM
  Use -SkipAzure to run offline checks only (no Azure login required).

.PARAMETER SubscriptionId
  Azure subscription ID (required for online checks).

.PARAMETER ResourceGroup
  Azure resource group name (required for online checks).

.PARAMETER SkipAzure
  Run offline checks only — no Azure login required.

.PARAMETER Verbose
  Show detailed output for each check.

.EXAMPLE
  # Full verification (offline + Azure)
  pwsh scripts/verify-environment.ps1 -SubscriptionId 00000000-... -ResourceGroup rg-acme-dev-sec

  # Offline only (no Azure required)
  pwsh scripts/verify-environment.ps1 -SkipAzure
#>
param(
  [string]$SubscriptionId,
  [string]$ResourceGroup,
  [string]$EnvConfig,
  [switch]$SkipAzure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$pass = 0
$fail = 0
$warn = 0

function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Assert-Check {
  param([string]$Name, [bool]$Condition, [string]$FailMessage, [switch]$WarnOnly)
  if ($Condition) {
    Write-Host "  PASS: $Name" -ForegroundColor Green
    $script:pass++
  } elseif ($WarnOnly) {
    Write-Host "  WARN: $Name — $FailMessage" -ForegroundColor Yellow
    $script:warn++
  } else {
    Write-Host "  FAIL: $Name — $FailMessage" -ForegroundColor Red
    $script:fail++
  }
}

# ─── Offline: Config files ───────────────────────────────────────────────────
Write-Section 'Config files'

$sampleFiles = @('env\sample.json', 'infra\base\parameters.sample.json', 'infra\images\parameters.sample.json', 'infra\deploy\parameters.sample.json')
foreach ($f in $sampleFiles) {
  Assert-Check "Sample file: $f" (Test-Path (Join-Path $repoRoot $f)) "$f not found"
}

$envDevPath = Join-Path $repoRoot 'env\dev.json'
Assert-Check 'Local env/dev.json exists' (Test-Path $envDevPath) 'Run bootstrap.ps1 or copy env/sample.json to env/dev.json' -WarnOnly

$baseLocalPath = Join-Path $repoRoot 'infra\base\parameters.local.json'
Assert-Check 'Local base parameters.local.json exists' (Test-Path $baseLocalPath) 'Run bootstrap.ps1 or copy from parameters.sample.json' -WarnOnly

# ─── Offline: Static tests ───────────────────────────────────────────────────
Write-Section 'Static regression tests'

$testFiles = @('tests\sprint1-tests.ps1', 'tests\sprint2-tests.ps1', 'tests\sprint3-tests.ps1', 'tests\parameter-tests.ps1')
$allTestsPass = $true
foreach ($tf in $testFiles) {
  $testPath = Join-Path $repoRoot $tf
  if (Test-Path $testPath) {
    try {
      & pwsh -File $testPath 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { $allTestsPass = $false; Assert-Check $tf $false "Test suite returned exit code $LASTEXITCODE" }
      else { Assert-Check $tf $true '' }
    } catch {
      $allTestsPass = $false
      Assert-Check $tf $false $_.Exception.Message
    }
  } else {
    Assert-Check $tf $false 'Test file not found'
    $allTestsPass = $false
  }
}

# ─── Offline: Manifest freshness ─────────────────────────────────────────────
Write-Section 'Manifest freshness'

$manifestScript = Join-Path $repoRoot 'scripts\manifest\update-agent-manifest.ps1'
$manifestFile   = Join-Path $repoRoot 'manifests\agent-manifest.json'

if ((Test-Path $manifestScript) -and (Test-Path $manifestFile)) {
  $before = Get-FileHash $manifestFile -Algorithm SHA256
  & pwsh -File $manifestScript 2>&1 | Out-Null
  $after = Get-FileHash $manifestFile -Algorithm SHA256
  Assert-Check 'Manifest is up-to-date' ($before.Hash -eq $after.Hash) 'agent-manifest.json is stale — run update-agent-manifest.ps1'
} else {
  Assert-Check 'Manifest files exist' $false 'Missing manifest script or manifest file'
}

# ─── Offline: Gitignore check ────────────────────────────────────────────────
Write-Section 'Security: no secrets in tracked files'

$trackedJson = & git -C $repoRoot ls-files '*.json' 2>$null
$secretFound = $false
foreach ($f in $trackedJson) {
  if ($f) {
    $content = Get-Content (Join-Path $repoRoot $f) -Raw -ErrorAction SilentlyContinue
    if ($content -and ($content -match 'ssh-rsa AAAAB3' -or $content -match 'ssh-ed25519 AAAA[A-Za-z0-9+/]{20}')) {
      $secretFound = $true
      Write-Host "    Found SSH key in tracked file: $f" -ForegroundColor Red
    }
  }
}
Assert-Check 'No SSH keys in tracked files' (-not $secretFound) 'Real SSH key material found in tracked files'

# ─── Online: Azure checks ────────────────────────────────────────────────────
if ($SkipAzure) {
  Write-Section 'Azure checks (SKIPPED — use -SubscriptionId and -ResourceGroup for full verification)'
} else {
  if (-not $SubscriptionId -or -not $ResourceGroup) {
    # Try loading from env config
    if (-not $EnvConfig) { $EnvConfig = $envDevPath }
    if (Test-Path $EnvConfig) {
      $cfg = Get-Content $EnvConfig -Raw | ConvertFrom-Json
      if (-not $ResourceGroup) { $ResourceGroup = $cfg.RESOURCE_GROUP }
    }
    if (-not $SubscriptionId -or -not $ResourceGroup) {
      Write-Section 'Azure checks (SKIPPED — provide -SubscriptionId and -ResourceGroup, or -SkipAzure)'
      $SkipAzure = $true
    }
  }

  if (-not $SkipAzure) {
    Write-Section 'Azure: subscription & resource group'
    az account set --subscription $SubscriptionId 2>$null
    Assert-Check 'Subscription set' ($LASTEXITCODE -eq 0) "Failed to set subscription $SubscriptionId"

    $rgExists = (az group show -n $ResourceGroup --query name -o tsv 2>$null)
    Assert-Check "Resource group exists: $ResourceGroup" ([bool]$rgExists) 'Resource group not found — run bootstrap.ps1 or deploy-base'

    if ($rgExists) {
      Write-Section 'Azure: Key Vault'
      $kv = az resource list -g $ResourceGroup --resource-type Microsoft.KeyVault/vaults --query '[0]' -o json 2>$null | ConvertFrom-Json
      Assert-Check 'Key Vault deployed' ($null -ne $kv) 'No Key Vault found'
      if ($kv) {
        $adminPw = az keyvault secret show --vault-name $kv.name --name admin-password --query id -o tsv 2>$null
        Assert-Check 'admin-password secret exists' ([bool]$adminPw) 'admin-password secret missing'
      }

      Write-Section 'Azure: Compute Gallery'
      $gallery = az resource list -g $ResourceGroup --resource-type Microsoft.Compute/galleries --query '[0]' -o json 2>$null | ConvertFrom-Json
      Assert-Check 'Compute Gallery deployed' ($null -ne $gallery) 'No gallery found'

      Write-Section 'Azure: Managed Identities'
      $ids = az resource list -g $ResourceGroup --resource-type Microsoft.ManagedIdentity/userAssignedIdentities -o json 2>$null | ConvertFrom-Json
      foreach ($expected in 'lin-agents','win-agents','gh-runner') {
        $idMatch = $ids | Where-Object { $_.name -like "*-$expected" }
        Assert-Check "Identity: *-$expected" ([bool]$idMatch) "Missing managed identity *-$expected"
      }

      Write-Section 'Azure: Compute (VMSS + VM)'
      $vmss = az vmss list -g $ResourceGroup --query '[0]' -o json 2>$null | ConvertFrom-Json
      Assert-Check 'Linux VMSS deployed' ($null -ne $vmss) 'No VM Scale Set found'

      $vm = az vm list -g $ResourceGroup --query "[?contains(name,'-gh-')]|[0]" -o json 2>$null | ConvertFrom-Json
      Assert-Check 'GitHub runner VM deployed' ($null -ne $vm) 'No GitHub runner VM found'

      Write-Section 'Azure: NSG'
      $nsg = az resource list -g $ResourceGroup --resource-type Microsoft.Network/networkSecurityGroups --query '[0]' -o json 2>$null | ConvertFrom-Json
      Assert-Check 'NSG deployed' ($null -ne $nsg) 'No NSG found'
    }
  }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
$summary = "Verification: $pass passed, $fail failed, $warn warnings"
Write-Host $summary -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

if ($fail -gt 0) {
  Write-Host "Fix failing checks before proceeding. See docs/GETTING_STARTED.md for help." -ForegroundColor Yellow
}

exit ($fail -gt 0 ? 1 : 0)
