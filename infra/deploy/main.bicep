@description('Org (match earlier stages)')
param org string
@description('Environment code')
param env string
@description('Azure region')
param location string
@description('Short region code for names')
param loc string
@description('Unique suffix used previously (must match gallery/key vault names)')
param uniqueSuffix string

@description('Admin username for all VMs')
param adminUsername string
@description('SSH public key for Linux agents')
param adminSshPublicKey string
@secure()
@description('Admin password (used for Windows + optional Linux fallback)')
param adminPassword string

@description('Linux gallery image version (e.g. 2025.09.05.1)')
param linuxImageVersion string
@description('Windows gallery image version')
param windowsImageVersion string

@description('Linux VM size override')
param linuxVmSize string = 'Standard_D4s_v5'
@description('Windows VM size override')
param windowsVmSize string = 'Standard_D4s_v5'

@description('Enable public IP for GitHub runner VM')
param enableGhPublicIp bool = false

@description('Supply true to confirm gallery use (safety gate)')
@allowed([ true ])
param confirmUseGallery bool = true

// Derived param passed through
var useGalleryImages = true

// Module name encodes confirmation selection for traceability
module base '../base/main.bicep' = {
  name: 'deploy-base-from-gallery-${bool(confirmUseGallery) ? 'confirm' : 'reject'}'
  params: {
    org: org
    env: env
    location: location
    loc: loc
    uniqueSuffix: uniqueSuffix
    adminUsername: adminUsername
    adminSshPublicKey: adminSshPublicKey
    adminPassword: adminPassword
    linuxImageVersion: linuxImageVersion
    windowsImageVersion: windowsImageVersion
    linuxVmSize: linuxVmSize
    windowsVmSize: windowsVmSize
    enableGhPublicIp: enableGhPublicIp
    useGalleryImages: useGalleryImages
  }
}

// Outputs
output vmssName string = base.outputs.vmssNameOut
output ghVmName string = base.outputs.ghVmNameOut
output keyVaultName string = base.outputs.keyVaultName
