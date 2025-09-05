param(
  [Parameter(Mandatory)][string]$ResourceGroup,
  [Parameter(Mandatory)][string]$Org,
  [Parameter(Mandatory)][string]$Env,
  [Parameter(Mandatory)][string]$Location,
  [Parameter(Mandatory)][string]$Loc,
  [Parameter(Mandatory)][string]$UniqueSuffix,
  [Parameter(Mandatory)][string]$AdminUsername,
  [Parameter(Mandatory)][string]$AdminSshPublicKey,
  [Parameter(Mandatory)][System.Security.SecureString]$AdminPassword,
  [string]$GalleryName,
  [string]$LinuxImageDefinition = 'linux-agent',
  [string]$WindowsImageDefinition = 'windows-agent'
)

$ErrorActionPreference = 'Stop'

if (-not $GalleryName) { $GalleryName = ("gal{0}{1}{2}{3}" -f $Org,$Env,$Loc,$UniqueSuffix).ToLower() }

Write-Host "Resolving latest gallery versions in '$GalleryName'..." -ForegroundColor Cyan
$linuxVer = az sig image-version list -g $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $LinuxImageDefinition --query '[-1].name' -o tsv
$winVer   = az sig image-version list -g $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $WindowsImageDefinition --query '[-1].name' -o tsv

if (-not $linuxVer -or -not $winVer) {
  throw "Could not resolve both gallery versions (linux='$linuxVer' windows='$winVer'). Ensure images are built."
}

$tempParamFile = Join-Path $env:TEMP ("deploy-gallery-{0}.json" -f ([guid]::NewGuid()))

if (-not $AdminPassword) { throw 'AdminPassword is required' }
$plainPw = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))

$paramObject = @{
  "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#"
  contentVersion = "1.0.0.0"
  parameters = @{
    org = @{ value = $Org }
    env = @{ value = $Env }
    location = @{ value = $Location }
    loc = @{ value = $Loc }
    uniqueSuffix = @{ value = $UniqueSuffix }
    adminUsername = @{ value = $AdminUsername }
    adminSshPublicKey = @{ value = $AdminSshPublicKey }
  adminPassword = @{ value = $plainPw }
    linuxImageVersion = @{ value = $linuxVer }
    windowsImageVersion = @{ value = $winVer }
    linuxVmSize = @{ value = 'Standard_D4s_v5' }
    windowsVmSize = @{ value = 'Standard_D4s_v5' }
    enableGhPublicIp = @{ value = $false }
    confirmUseGallery = @{ value = $true }
  }
} | ConvertTo-Json -Depth 8

$paramObject | Out-File -FilePath $tempParamFile -Encoding utf8
Write-Host "Parameters written: $tempParamFile" -ForegroundColor Yellow

Write-Host "Starting deployment (gallery versions linux=$linuxVer windows=$winVer)" -ForegroundColor Green
az deployment group create -g $ResourceGroup -f "infra/deploy/main.bicep" -p @$tempParamFile

Write-Host "Deployment complete." -ForegroundColor Green
