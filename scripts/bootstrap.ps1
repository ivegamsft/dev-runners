<#
.SYNOPSIS
  Bootstrap a new dev-runners environment from scratch.

.DESCRIPTION
  Guides you from zero to a working deployment:
  1. Checks prerequisites (az, gh, pwsh, jq, packer)
  2. Creates local config files (env/dev.json, parameters.local.json)
  3. Creates Azure resource group
  4. Sets up OIDC (Entra app + federated credential)
  5. Configures GitHub repo variables and secrets
  6. Runs first base deployment

  Only -Org, -SubscriptionId, -GitHubRepo, and -AdminSshPublicKeyFile are
  truly required. Everything else has sensible defaults or is derived/generated.

.PARAMETER Org
  Short org identifier (lowercase, alphanumeric). Required.

.PARAMETER SubscriptionId
  Azure subscription ID. Required.

.PARAMETER GitHubRepo
  GitHub repo in owner/repo format. Required.

.PARAMETER AdminSshPublicKeyFile
  Path to SSH public key file for Linux VMs. Required.

.PARAMETER Env
  Environment code. Default: dev

.PARAMETER Location
  Azure region. Default: current az CLI default or eastus2.

.PARAMETER Loc
  Short region code for naming. Auto-derived from Location if omitted.

.PARAMETER UniqueSuffix
  Random 3-12 char suffix for global uniqueness. Auto-generated if omitted.

.PARAMETER AdminUsername
  VM admin username. Default: azureadmin

.PARAMETER SkipDeploy
  Skip the initial base deployment (just configure).

.PARAMETER WhatIf
  Preview actions without making changes.

.EXAMPLE
  # Minimal — only the 4 required params, everything else derived/generated:
  ./bootstrap.ps1 -Org myorg -SubscriptionId 00000000-0000-0000-0000-000000000000 -GitHubRepo yourorg/dev-runners -AdminSshPublicKeyFile ~/.ssh/id_rsa.pub

  # Full override:
  ./bootstrap.ps1 -Org myorg -Env prod -Location westeurope -Loc weu -UniqueSuffix x7k2 -AdminUsername youruser -SubscriptionId 00000000-0000-0000-0000-000000000000 -GitHubRepo yourorg/dev-runners -AdminSshPublicKeyFile ~/.ssh/id_rsa.pub
#>
param(
  [Parameter(Mandatory)][string]$Org,
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$GitHubRepo,
  [Parameter(Mandatory)][string]$AdminSshPublicKeyFile,
  [string]$Env = 'dev',
  [string]$Location,
  [string]$Loc,
  [string]$UniqueSuffix,
  [string]$AdminUsername = 'azureadmin',
  [switch]$SkipDeploy,
  [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent

function Write-Step($msg) { Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    SKIP: $msg" -ForegroundColor Yellow }

# ─── 1. Prerequisites ────────────────────────────────────────────────────────
Write-Step '1. Checking prerequisites'

$prereqs = @(
  @{ cmd='az';     check={ az version -o tsv 2>$null };        name='Azure CLI' },
  @{ cmd='gh';     check={ gh --version 2>$null };             name='GitHub CLI' },
  @{ cmd='pwsh';   check={ $PSVersionTable.PSVersion };        name='PowerShell 7+' },
  @{ cmd='jq';     check={ jq --version 2>$null };             name='jq' },
  @{ cmd='packer'; check={ packer version 2>$null };           name='Packer' }
)

$missing = @()
foreach ($p in $prereqs) {
  try {
    $null = & $p.check
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'fail' }
    Write-Ok $p.name
  } catch {
    Write-Host "    MISSING: $($p.name) ($($p.cmd))" -ForegroundColor Red
    $missing += $p.name
  }
}
if ($missing.Count -gt 0) {
  Write-Host "`nInstall missing prerequisites: $($missing -join ', ')" -ForegroundColor Red
  Write-Host "See docs/GETTING_STARTED.md for installation links." -ForegroundColor Yellow
  exit 1
}

# ─── 2. Derive and generate defaults ──────────────────────────────────────────
Write-Step '2. Resolving parameters'

# Location: default from az CLI config, fallback to eastus2
if (-not $Location) {
  $Location = (az config get defaults.location --query value -o tsv 2>$null)
  if (-not $Location) { $Location = 'eastus2' }
  Write-Ok "Location (auto): $Location"
} else { Write-Ok "Location: $Location" }

# Loc: derive short code from Azure region using CAF abbreviations
if (-not $Loc) {
  $regionMap = @{
    # Americas
    eastus='eus'; eastus2='eus2'; westus='wus'; westus2='wus2'; westus3='wus3'
    centralus='cus'; northcentralus='ncus'; southcentralus='scus'; westcentralus='wcus'
    canadacentral='cnc'; canadaeast='cne'
    brazilsouth='brs'; brazilsoutheast='brse'
    # Europe
    northeurope='ne'; westeurope='we'; uksouth='uks'; ukwest='ukw'
    francecentral='frc'; francesouth='frs'; germanywestcentral='gwc'; germanynorth='gn'
    swedencentral='swc'; switzerlandnorth='szn'; switzerlandwest='szw'
    norwayeast='nwe'; norwaywest='nww'; polandcentral='plc'; italynorth='itn'
    spaincentral='spc'
    # Asia Pacific
    australiaeast='ae'; australiasoutheast='ase'; australiacentral='acl'
    eastasia='ea'; southeastasia='sea'
    japaneast='jpe'; japanwest='jpw'
    koreacentral='krc'; koreasouth='krs'
    centralindia='inc'; southindia='ins'; westindia='inw'
    # Middle East & Africa
    southafricanorth='san'; southafricawest='saw'
    uaenorth='uan'; uaecentral='uac'
    qatarcentral='qac'; israelcentral='ilc'
  }
  $Loc = $regionMap[$Location]
  if (-not $Loc) {
    # Fallback: first 3-4 chars stripped of vowels
    $Loc = ($Location -replace '[aeiou\-]','').Substring(0, [Math]::Min(4, ($Location -replace '[aeiou\-]','').Length))
  }
  Write-Ok "Loc (derived from $Location): $Loc"
} else { Write-Ok "Loc: $Loc" }

# UniqueSuffix: generate 4-char random alphanumeric
if (-not $UniqueSuffix) {
  $UniqueSuffix = -join ((97..122) + (48..57) | Get-Random -Count 4 | ForEach-Object { [char]$_ })
  Write-Ok "UniqueSuffix (generated): $UniqueSuffix"
} else { Write-Ok "UniqueSuffix: $UniqueSuffix" }

Write-Ok "Env: $Env"
Write-Ok "AdminUsername: $AdminUsername"

# ─── 3. Validate inputs ──────────────────────────────────────────────────────
Write-Step '3. Validating inputs'

if (-not (Test-Path $AdminSshPublicKeyFile)) {
  throw "SSH public key file not found: $AdminSshPublicKeyFile"
}
$sshPubKey = (Get-Content $AdminSshPublicKeyFile -Raw).Trim()
if ($sshPubKey -notmatch '^ssh-(rsa|ed25519|ecdsa)') {
  throw "Invalid SSH public key format in $AdminSshPublicKeyFile"
}

$gitHubParts = $GitHubRepo -split '/'
if ($gitHubParts.Count -ne 2) {
  throw "GitHubRepo must be in owner/repo format. Got: $GitHubRepo"
}
$ghOwner = $gitHubParts[0]
$ghRepo  = $gitHubParts[1]

$resourceGroup = "rg-$Org-$Env-$Loc"
$galleryName   = "gal$Org$Env$Loc$UniqueSuffix"

Write-Ok "Resource Group: $resourceGroup"
Write-Ok "Gallery: $galleryName"
Write-Ok "SSH key: $AdminSshPublicKeyFile"

# ─── 3. Copy sample files ────────────────────────────────────────────────────
Write-Step '3. Creating local config files from samples'

$envDevJson = Join-Path $repoRoot 'env\dev.json'
if (-not (Test-Path $envDevJson)) {
  $envConfig = @{
    ORG           = $Org
    ENV           = $Env
    LOCATION      = $Location
    LOC           = $Loc
    UNIQUE_SUFFIX = $UniqueSuffix
    RESOURCE_GROUP = $resourceGroup
    GALLERY_NAME  = $galleryName
    PACKER_TEMP_RG = 'rg-packer-temp'
    PACKER_VM_SIZE = 'Standard_D4s_v5'
    ADMIN_USERNAME = $AdminUsername
  }
  if ($WhatIf) { Write-Skip "Would create $envDevJson" }
  else {
    $envConfig | ConvertTo-Json -Depth 3 | Out-File $envDevJson -Encoding utf8
    Write-Ok "Created $envDevJson"
  }
} else { Write-Skip "$envDevJson already exists" }

# Base parameters
$baseLocal = Join-Path $repoRoot 'infra\base\parameters.local.json'
if (-not (Test-Path $baseLocal)) {
  $baseParams = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
      org                      = @{ value = $Org }
      env                      = @{ value = $Env }
      location                 = @{ value = $Location }
      loc                      = @{ value = $Loc }
      uniqueSuffix             = @{ value = $UniqueSuffix }
      adminUsername             = @{ value = $AdminUsername }
      adminSshPublicKey        = @{ value = $sshPubKey }
      linuxUsePassword         = @{ value = $false }
      linuxVmSize              = @{ value = 'Standard_D4s_v5' }
      windowsVmSize            = @{ value = 'Standard_D4s_v5' }
      enableGhPublicIp         = @{ value = $false }
      keyVaultSku              = @{ value = 'standard' }
      vnetAddressSpace         = @{ value = '10.20.0.0/16' }
      subnetAgentsCidr         = @{ value = '10.20.1.0/24' }
      linuxImageDefinitionName = @{ value = 'linux-agent' }
      windowsImageDefinitionName = @{ value = 'windows-agent' }
      linuxImageVersion        = @{ value = 'latest' }
      windowsImageVersion      = @{ value = 'latest' }
      useGalleryImages         = @{ value = $false }
      createGallery            = @{ value = $true }
    }
  }
  if ($WhatIf) { Write-Skip "Would create $baseLocal" }
  else {
    $baseParams | ConvertTo-Json -Depth 5 | Out-File $baseLocal -Encoding utf8
    Write-Ok "Created $baseLocal"
  }
} else { Write-Skip "$baseLocal already exists" }

# Images parameters
$imagesLocal = Join-Path $repoRoot 'infra\images\parameters.local.json'
if (-not (Test-Path $imagesLocal)) {
  $imgParams = @{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = @{
      org            = @{ value = $Org }
      env            = @{ value = $Env }
      location       = @{ value = $Location }
      loc            = @{ value = $Loc }
      uniqueSuffix   = @{ value = $UniqueSuffix }
      galleryName    = @{ value = $galleryName }
      linuxImageDefinitionName  = @{ value = 'linux-agent' }
      windowsImageDefinitionName = @{ value = 'windows-agent' }
    }
  }
  if ($WhatIf) { Write-Skip "Would create $imagesLocal" }
  else {
    $imgParams | ConvertTo-Json -Depth 5 | Out-File $imagesLocal -Encoding utf8
    Write-Ok "Created $imagesLocal"
  }
} else { Write-Skip "$imagesLocal already exists" }

# ─── 4. Azure Login & Resource Group ─────────────────────────────────────────
Write-Step '4. Azure: subscription & resource group'

if ($WhatIf) {
  Write-Skip "Would set subscription to $SubscriptionId"
  Write-Skip "Would create resource group $resourceGroup in $Location"
} else {
  az account set --subscription $SubscriptionId
  Write-Ok "Subscription: $SubscriptionId"

  if (-not (az group show -n $resourceGroup --query name -o tsv 2>$null)) {
    az group create -n $resourceGroup -l $Location --tags org=$Org env=$Env loc=$Loc system=build-agents | Out-Null
    Write-Ok "Created resource group: $resourceGroup"
  } else { Write-Ok "Resource group already exists: $resourceGroup" }
}

# ─── 5. OIDC Setup ───────────────────────────────────────────────────────────
Write-Step '5. Setting up OIDC (Entra app + federated credential)'

$oidcScript = Join-Path $PSScriptRoot 'identity\setup-github-oidc.ps1'
$displayName = "gh-oidc-$Org-$Env"

if ($WhatIf) {
  Write-Skip "Would run: setup-github-oidc.ps1 -DisplayName $displayName -GitHubOrg $ghOwner -GitHubRepo $ghRepo -ResourceGroup $resourceGroup"
} else {
  $oidcResult = & $oidcScript `
    -DisplayName $displayName `
    -GitHubOrg $ghOwner `
    -GitHubRepo $ghRepo `
    -Branch main `
    -ResourceGroup $resourceGroup `
    -Roles Contributor | ConvertFrom-Json

  $clientId = $oidcResult.appId
  $tenantId = (az account show --query tenantId -o tsv)
  Write-Ok "OIDC App: $displayName (clientId: $clientId)"
}

# ─── 6. GitHub Configuration ─────────────────────────────────────────────────
Write-Step '6. Configuring GitHub repository variables and secrets'

if ($WhatIf) {
  Write-Skip "Would set GitHub variables: ORG, ENV, LOCATION, LOC, UNIQUE_SUFFIX, etc."
  Write-Skip "Would set GitHub secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, ADMIN_SSH_PUBLIC_KEY"
} else {
  $ghVars = @{
    ORG           = $Org
    ENV           = $Env
    LOCATION      = $Location
    LOC           = $Loc
    UNIQUE_SUFFIX = $UniqueSuffix
    RESOURCE_GROUP = $resourceGroup
    GALLERY_NAME  = $galleryName
    PACKER_TEMP_RG = 'rg-packer-temp'
    PACKER_VM_SIZE = 'Standard_D4s_v5'
    ADMIN_USERNAME = $AdminUsername
  }
  foreach ($kv in $ghVars.GetEnumerator()) {
    gh variable set $kv.Key --body $kv.Value --repo $GitHubRepo 2>$null
    Write-Ok "Variable: $($kv.Key)"
  }

  gh secret set AZURE_CLIENT_ID --body $clientId --repo $GitHubRepo
  gh secret set AZURE_TENANT_ID --body $tenantId --repo $GitHubRepo
  gh secret set AZURE_SUBSCRIPTION_ID --body $SubscriptionId --repo $GitHubRepo
  gh secret set ADMIN_SSH_PUBLIC_KEY --body $sshPubKey --repo $GitHubRepo
  Write-Ok "Secrets: AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, ADMIN_SSH_PUBLIC_KEY"
}

# ─── 7. Initial Deployment ───────────────────────────────────────────────────
if ($SkipDeploy) {
  Write-Step '7. Skipping initial deployment (-SkipDeploy)'
} else {
  Write-Step '7. Running initial base deployment'

  $deployScript = Join-Path $PSScriptRoot 'deploy\deploy-base.ps1'
  if ($WhatIf) {
    Write-Skip "Would run: deploy-base.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $resourceGroup -WhatIf"
  } else {
    & $deployScript `
      -SubscriptionId $SubscriptionId `
      -ResourceGroup $resourceGroup `
      -Location $Location
    Write-Ok 'Base deployment complete'
  }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Step 'Bootstrap complete!'
Write-Host @"

  Environment:      $Org-$Env ($Location)
  Resource Group:   $resourceGroup
  Gallery:          $galleryName
  GitHub Repo:      $GitHubRepo

  Next steps:
    1. Run validation:   pwsh scripts/verify-environment.ps1 -SubscriptionId $SubscriptionId -ResourceGroup $resourceGroup
    2. Build images:     Trigger 'Build and Publish Agent Images' workflow
    3. Deploy gallery:   Trigger 'Deploy Base Infra (Gallery Images)' workflow
    4. Run all tests:    pwsh tests/sprint1-tests.ps1 && pwsh tests/sprint2-tests.ps1 && pwsh tests/sprint3-tests.ps1

  Cleanup when done: pwsh scripts/cleanup.ps1 -SubscriptionId $SubscriptionId -Org $Org -Env $Env -Loc $Loc -GitHubRepo $GitHubRepo
"@ -ForegroundColor White
