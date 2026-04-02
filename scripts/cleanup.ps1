<#
.SYNOPSIS
  Clean up / tear down a dev-runners environment.

.DESCRIPTION
  Removes Azure resources and optionally GitHub configuration:
  1. Deletes the Azure resource group (all resources within it)
  2. Optionally removes the Packer temp resource group
  3. Optionally removes the Entra ID app + service principal (OIDC)
  4. Optionally clears GitHub repo variables and secrets

  Use -WhatIf to preview without making changes.
  Use -IncludeOidc to also remove the Entra app and federated credential.
  Use -IncludeGitHub to also clear GitHub variables/secrets.

.PARAMETER SubscriptionId
  Azure subscription ID.

.PARAMETER Org
  Short org identifier used during bootstrap.

.PARAMETER Env
  Environment code used during bootstrap.

.PARAMETER Loc
  Short region code used during bootstrap.

.PARAMETER GitHubRepo
  GitHub repo in owner/repo format (required for -IncludeGitHub).

.PARAMETER IncludeOidc
  Also delete the Entra ID OIDC app registration.

.PARAMETER IncludeGitHub
  Also clear GitHub repo variables and secrets.

.PARAMETER IncludePackerRg
  Also delete the Packer temp resource group.

.PARAMETER Force
  Skip confirmation prompts.

.PARAMETER WhatIf
  Preview actions without making changes.

.EXAMPLE
  # Basic cleanup (Azure RG only)
  pwsh scripts/cleanup.ps1 -SubscriptionId 00000000-... -Org myorg -Env dev -Loc eus2

  # Full cleanup (Azure + OIDC + GitHub)
  pwsh scripts/cleanup.ps1 -SubscriptionId 00000000-... -Org myorg -Env dev -Loc eus2 -GitHubRepo yourorg/dev-runners -IncludeOidc -IncludeGitHub -Force
#>
param(
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$Org,
  [Parameter(Mandatory)][string]$Env,
  [Parameter(Mandatory)][string]$Loc,
  [string]$GitHubRepo,
  [switch]$IncludeOidc,
  [switch]$IncludeGitHub,
  [switch]$IncludePackerRg,
  [switch]$Force,
  [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($msg)    { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Skip($msg)    { Write-Host "    SKIP: $msg" -ForegroundColor Yellow }
function Write-Removed($msg) { Write-Host "    REMOVED: $msg" -ForegroundColor Red }

$resourceGroup = "rg-$Org-$Env-$Loc"
$displayName   = "gh-oidc-$Org-$Env"
$packerRg      = 'rg-packer-temp'

# ─── Confirmation ─────────────────────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Red
Write-Host " CLEANUP — This will DESTROY resources" -ForegroundColor Red
Write-Host "========================================`n" -ForegroundColor Red

$targets = @("Azure Resource Group: $resourceGroup")
if ($IncludePackerRg)  { $targets += "Packer Temp RG: $packerRg" }
if ($IncludeOidc)      { $targets += "Entra App: $displayName" }
if ($IncludeGitHub)    { $targets += "GitHub Variables/Secrets: $GitHubRepo" }

Write-Host "Targets:" -ForegroundColor Yellow
$targets | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }

if (-not $Force -and -not $WhatIf) {
  $confirm = Read-Host "`nType 'yes' to confirm cleanup"
  if ($confirm -ne 'yes') {
    Write-Host 'Cleanup cancelled.' -ForegroundColor Yellow
    exit 0
  }
}

# ─── 1. Azure Login ──────────────────────────────────────────────────────────
Write-Step '1. Setting Azure subscription'
if ($WhatIf) {
  Write-Skip "Would set subscription to $SubscriptionId"
} else {
  az account set --subscription $SubscriptionId
  Write-Ok "Subscription: $SubscriptionId"
}

# ─── 2. Delete Resource Group ────────────────────────────────────────────────
Write-Step "2. Deleting resource group: $resourceGroup"

if ($WhatIf) {
  Write-Skip "Would delete resource group $resourceGroup and all resources within"
} else {
  $rgExists = (az group show -n $resourceGroup --query name -o tsv 2>$null)
  if ($rgExists) {
    Write-Host "    Deleting $resourceGroup (this may take several minutes)..." -ForegroundColor Yellow
    az group delete -n $resourceGroup --yes --no-wait
    Write-Removed $resourceGroup
  } else {
    Write-Skip "Resource group $resourceGroup not found"
  }
}

# ─── 3. Delete Packer Temp RG ────────────────────────────────────────────────
if ($IncludePackerRg) {
  Write-Step "3. Deleting Packer temp resource group: $packerRg"
  if ($WhatIf) {
    Write-Skip "Would delete $packerRg"
  } else {
    $prExists = (az group show -n $packerRg --query name -o tsv 2>$null)
    if ($prExists) {
      az group delete -n $packerRg --yes --no-wait
      Write-Removed $packerRg
    } else {
      Write-Skip "$packerRg not found"
    }
  }
} else {
  Write-Step '3. Packer temp RG (skipped — use -IncludePackerRg)'
}

# ─── 4. Remove OIDC App ──────────────────────────────────────────────────────
if ($IncludeOidc) {
  Write-Step "4. Removing Entra app: $displayName"
  if ($WhatIf) {
    Write-Skip "Would delete Entra app '$displayName' and its service principal"
  } else {
    $app = az ad app list --display-name $displayName --query '[0]' -o json 2>$null | ConvertFrom-Json
    if ($app) {
      # Delete SP first
      $sp = az ad sp list --filter "appId eq '$($app.appId)'" --query '[0].id' -o tsv 2>$null
      if ($sp) {
        az ad sp delete --id $sp 2>$null
        Write-Removed "Service principal for $displayName"
      }
      az ad app delete --id $app.id
      Write-Removed "Entra app: $displayName (appId: $($app.appId))"
    } else {
      Write-Skip "Entra app '$displayName' not found"
    }
  }
} else {
  Write-Step '4. OIDC app (skipped — use -IncludeOidc)'
}

# ─── 5. Clear GitHub Config ──────────────────────────────────────────────────
if ($IncludeGitHub) {
  if (-not $GitHubRepo) {
    Write-Host "    ERROR: -GitHubRepo is required with -IncludeGitHub" -ForegroundColor Red
    exit 1
  }

  Write-Step "5. Clearing GitHub config: $GitHubRepo"
  if ($WhatIf) {
    Write-Skip "Would remove GitHub variables and secrets for $GitHubRepo"
  } else {
    $vars = @('ORG','ENV','LOCATION','LOC','UNIQUE_SUFFIX','RESOURCE_GROUP','GALLERY_NAME','PACKER_TEMP_RG','PACKER_VM_SIZE','ADMIN_USERNAME')
    foreach ($v in $vars) {
      gh variable delete $v --repo $GitHubRepo 2>$null
    }
    Write-Removed "GitHub variables: $($vars -join ', ')"

    $secrets = @('AZURE_CLIENT_ID','AZURE_TENANT_ID','AZURE_SUBSCRIPTION_ID','ADMIN_SSH_PUBLIC_KEY')
    foreach ($s in $secrets) {
      gh secret delete $s --repo $GitHubRepo 2>$null
    }
    Write-Removed "GitHub secrets: $($secrets -join ', ')"
  }
} else {
  Write-Step '5. GitHub config (skipped — use -IncludeGitHub)'
}

# ─── 6. Local file cleanup ───────────────────────────────────────────────────
Write-Step '6. Local files'
$repoRoot = Split-Path $PSScriptRoot -Parent
$localFiles = @('env\dev.json', 'infra\base\parameters.local.json', 'infra\images\parameters.local.json', 'infra\deploy\parameters.local.json')
$foundLocal = $localFiles | Where-Object { Test-Path (Join-Path $repoRoot $_) }
if ($foundLocal) {
  Write-Host "    Local config files still on disk (gitignored, safe to keep or delete manually):" -ForegroundColor Yellow
  $foundLocal | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
} else {
  Write-Ok 'No local config files found'
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Step 'Cleanup complete!'
if ($WhatIf) {
  Write-Host "`n  This was a dry run — no changes were made." -ForegroundColor Yellow
  Write-Host "  Remove -WhatIf to execute cleanup.`n" -ForegroundColor Yellow
} else {
  Write-Host @"

  Resource group deletion is async — it may take a few minutes to fully complete.
  Verify with: az group show -n $resourceGroup 2>&1 | Select-Object -First 1

  To remove local config files:
    Remove-Item env/dev.json, infra/*/parameters.local.json -ErrorAction SilentlyContinue
"@ -ForegroundColor White
}
