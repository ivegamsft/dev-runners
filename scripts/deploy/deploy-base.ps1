param(
  [string]$SubscriptionId = '844eabcc-dc96-453b-8d45-bef3d566f3f8',
  [string]$ResourceGroup = 'rg-acme-dev-sec',
  [string]$Location = 'swedencentral',
  [string]$ParametersFile = '..\..\infra\base\parameters.dev.json',
  [switch]$WhatIf
)

# Resolve paths relative to script root for reliability regardless of current working directory
if (-not [System.IO.Path]::IsPathRooted($ParametersFile)) {
  $ParametersFile = Join-Path $PSScriptRoot $ParametersFile
}
$TemplateFile = Join-Path $PSScriptRoot '..\..\infra\base\main.bicep'

if (-not (Test-Path $TemplateFile)) { throw "Template file not found: $TemplateFile" }
if (-not (Test-Path $ParametersFile)) { throw "Parameters file not found: $ParametersFile" }

Write-Host 'Setting subscription...' -ForegroundColor Cyan
az account set --subscription $SubscriptionId

if (-not (az group show -n $ResourceGroup --query name -o tsv 2>$null)) {
  Write-Host "Creating resource group $ResourceGroup in $Location" -ForegroundColor Cyan
  az group create -n $ResourceGroup -l $Location | Out-Null
}

$deploymentName = "base-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$whatIfFlag = $WhatIf.IsPresent ? '--what-if' : ''

Write-Host "Deploying base infra ($deploymentName)..." -ForegroundColor Cyan
az deployment group create `
  -g $ResourceGroup `
  -n $deploymentName `
  -f $TemplateFile `
  -p @$ParametersFile $whatIfFlag
