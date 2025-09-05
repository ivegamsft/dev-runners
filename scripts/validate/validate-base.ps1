param(
  [string]$SubscriptionId,
  [string]$ResourceGroup,
  [string]$ExpectedOrg = 'acme',
  [string]$ExpectedEnv = 'dev',
  [string]$ExpectedLoc = 'sec'
)

if (-not $SubscriptionId -or -not $ResourceGroup) {
  Write-Error 'SubscriptionId and ResourceGroup are required.'
  exit 1
}

az account set --subscription $SubscriptionId

if (-not (az group show -n $ResourceGroup --query name -o tsv 2>$null)) {
  Write-Error "Resource group $ResourceGroup not found. Deploy base infra first."; exit 2
}

Write-Host 'Fetching deployed resources...' -ForegroundColor Cyan
# (optional) all resources if needed for future checks
# $allResources = az resource list -g $ResourceGroup -o json | ConvertFrom-Json

function Assert-OrFail($condition, $message) {
  if (-not $condition) { Write-Error $message; $script:Failed = $true }
}

# Key Vault
$kv = az resource list -g $ResourceGroup --resource-type Microsoft.KeyVault/vaults --query '[0]' -o json | ConvertFrom-Json
Assert-OrFail ($null -ne $kv) 'Key Vault not found.'
if ($kv) {
  $kvName = $kv.name
  Assert-OrFail ($kvName.Length -ge 3 -and $kvName.Length -le 24 -and $kvName -match '^[a-z0-9]+$') "Key Vault name $kvName invalid format."
  $adminUserSecret = az keyvault secret show --vault-name $kvName --name admin-username --query value -o tsv 2>$null
  Assert-OrFail ($adminUserSecret) 'admin-username secret missing.'
  $adminPasswordSecret = az keyvault secret show --vault-name $kvName --name admin-password --query value -o tsv 2>$null
  Assert-OrFail ($adminPasswordSecret) 'admin-password secret missing (generation script failure?).'
}

# Gallery
$gallery = az resource list -g $ResourceGroup --resource-type Microsoft.Compute/galleries --query '[0]' -o json | ConvertFrom-Json
Assert-OrFail ($gallery) 'Compute Gallery missing.'

# Identities
$ids = az resource list -g $ResourceGroup --resource-type Microsoft.ManagedIdentity/userAssignedIdentities -o json | ConvertFrom-Json
foreach ($expected in 'lin-agents','win-agents','gh-runner','deploy') {
  $match = $ids | Where-Object { $_.name -like "*-$expected" }
  Assert-OrFail ($match) "User-assigned identity *-$expected missing."
}

# VMSS
$vmss = az vmss list -g $ResourceGroup --query '[0]' -o json | ConvertFrom-Json
Assert-OrFail ($vmss) 'VM Scale Set missing.'
if ($vmss) {
  $hasPasswordAuth = $vmss.virtualMachineProfile.osProfile.linuxConfiguration.disablePasswordAuthentication
  Assert-OrFail ($hasPasswordAuth -eq $true) 'Linux VMSS should have password auth disabled.'
}

# Windows VM
$vm = az vm list -g $ResourceGroup --query "[?contains(name,'-gh-')]|[0]" -o json | ConvertFrom-Json
Assert-OrFail ($vm) 'GitHub runner VM missing.'

# Tags spot check on Key Vault
if ($kv) {
  $tags = $kv.tags
  foreach ($t in @{'org'=$ExpectedOrg; 'env'=$ExpectedEnv; 'loc'=$ExpectedLoc; 'system'='build-agents'}) {
    $k=$t.Keys[0]; $v=$t[$k]; Assert-OrFail ($tags.$k -eq $v) "Tag $k expected $v got $($tags.$k)"
  }
}

if ($Failed) { Write-Host 'VALIDATION: FAILED' -ForegroundColor Red; exit 10 } else { Write-Host 'VALIDATION: PASSED' -ForegroundColor Green }