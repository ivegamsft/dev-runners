param(
  [string]$SubscriptionId = '844eabcc-dc96-453b-8d45-bef3d566f3f8',
  [string]$ResourceGroup = 'rg-acme-dev-sec',
  [string]$Location = 'swedencentral',
  [string]$ParametersFile = '..\..\infra\images\parameters.dev.json',
  [switch]$WhatIf
)

if (-not [System.IO.Path]::IsPathRooted($ParametersFile)) {
  $ParametersFile = Join-Path $PSScriptRoot $ParametersFile
}
$TemplateFile = Join-Path $PSScriptRoot '..\..\infra\images\main.bicep'

if (-not (Test-Path $TemplateFile)) { throw "Template file not found: $TemplateFile" }
if (-not (Test-Path $ParametersFile)) { throw "Parameters file not found: $ParametersFile" }

Write-Host 'Setting subscription...' -ForegroundColor Cyan
az account set --subscription $SubscriptionId

$deploymentName = "images-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$whatIfFlag = $WhatIf.IsPresent ? '--what-if' : ''

Write-Host "Deploying image definitions ($deploymentName)..." -ForegroundColor Cyan
az deployment group create `
  -g $ResourceGroup `
  -n $deploymentName `
  -f $TemplateFile `
  -p @$ParametersFile $whatIfFlag
