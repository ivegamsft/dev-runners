<#!
.SYNOPSIS
Creates or updates an Entra ID application & federated credential for GitHub Actions OIDC.

.DESCRIPTION
Idempotently:
 1. Creates App Registration (if missing)
 2. Ensures Service Principal exists
 3. Adds / updates federated credential for repo / branch reference
 4. Assigns configured Azure RBAC roles at a target scope (default: resource group)

Requires: Azure CLI (az) with sufficient directory privileges (App Registration + role assignment).

.PARAMETER DisplayName
App display name (unique in tenant).

.PARAMETER GitHubOrg
GitHub organization / user.

.PARAMETER GitHubRepo
Repository name (without org).

.PARAMETER Branch
Branch reference (defaults main). Use full ref path style when customizing (script composes refs/heads/<branch>). For environments / tags adjust Subject manually via -Subject override.

.PARAMETER Subject
Optional explicit subject for federated credential. If omitted: repo:<org>/<repo>:ref:refs/heads/<branch>

.PARAMETER Name
Federated credential name (default gh-main).

.PARAMETER Audience
OIDC audience (default api://AzureADTokenExchange).

.PARAMETER ResourceGroup
Primary resource group scope for role assignments.

.PARAMETER Roles
Array of Azure built-in role names to assign at scope.

.OUTPUTS
JSON with appId, objectId, federatedCredentialName.

Example:
  ./setup-github-oidc.ps1 -DisplayName gh-oidc-acme-dev -GitHubOrg ivegamsft -GitHubRepo dev-runners -Branch main -ResourceGroup rg-acme-dev-sec -Roles Contributor
#!>
param(
  [Parameter(Mandatory)][string]$DisplayName,
  [Parameter(Mandatory)][string]$GitHubOrg,
  [Parameter(Mandatory)][string]$GitHubRepo,
  [string]$Branch = 'main',
  [string]$Subject,
  [string]$Name = 'gh-main',
  [string]$Audience = 'api://AzureADTokenExchange',
  [Parameter(Mandatory)][string]$ResourceGroup,
  [string[]]$Roles = @('Contributor'),
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Write-Info($m){ Write-Host $m -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }

Write-Info 'Resolving existing application...'
$existing = az ad app list --display-name $DisplayName --query '[0]' -o json | ConvertFrom-Json
if(-not $existing){
  Write-Info 'Creating application registration'
  $existing = az ad app create --display-name $DisplayName -o json | ConvertFrom-Json
} else { Write-Info 'Application already exists (idempotent)'}

$appId = $existing.appId
$appObjectId = $existing.id
Write-Info "AppId: $appId"

# Ensure service principal
$sp = az ad sp list --filter "appId eq '$appId'" --query '[0]' -o json | ConvertFrom-Json
if(-not $sp){
  Write-Info 'Creating service principal'
  $sp = az ad sp create --id $appId -o json | ConvertFrom-Json
} else { Write-Info 'Service principal exists'}

if(-not $Subject){
  $Subject = "repo:$GitHubOrg/$GitHubRepo:ref:refs/heads/$Branch"
}

Write-Info "Federated credential subject: $Subject"
$fid = az ad app federated-credential list --id $appId -o json | ConvertFrom-Json | Where-Object { $_.name -eq $Name }
if($fid){
  Write-Info 'Updating existing federated credential'
  az ad app federated-credential delete --id $appId --federated-credential-id $Name | Out-Null
}

$tmp = New-TemporaryFile
@{
  name = $Name
  issuer = 'https://token.actions.githubusercontent.com'
  subject = $Subject
  audiences = @($Audience)
} | ConvertTo-Json | Out-File $tmp -Encoding utf8

Write-Info 'Creating federated credential'
az ad app federated-credential create --id $appId --parameters @$tmp | Out-Null
Remove-Item $tmp -Force

$scope = (az group show -n $ResourceGroup --query id -o tsv)
foreach($role in $Roles){
  Write-Info "Ensuring role '$role' at scope $scope"
  $ra = az role assignment list --assignee $sp.id --scope $scope --role "$role" -o json | ConvertFrom-Json
  if(-not $ra){
    if($WhatIf){ Write-Warn "(WhatIf) Would assign role $role" } else { az role assignment create --assignee-object-id $sp.id --assignee-principal-type ServicePrincipal --role "$role" --scope $scope | Out-Null }
  } else { Write-Info 'Role already assigned' }
}

$out = [pscustomobject]@{ appId = $appId; objectId = $sp.id; federatedCredential = $Name; subject = $Subject }
$out | ConvertTo-Json -Depth 5