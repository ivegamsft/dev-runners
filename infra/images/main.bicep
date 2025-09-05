@description('Org short code.')
param org string
@description('Environment code.')
param env string
@description('Deployment location.')
param location string = resourceGroup().location
@description('Region short code.')
param loc string
@description('Unique suffix reused (must match base).')
param uniqueSuffix string

@description('Gallery name must match base deployment output.')
param galleryName string

@description('Linux image definition name.')
param linuxImageDefinitionName string = 'linux-agent'
@description('Windows image definition name.')
param windowsImageDefinitionName string = 'windows-agent'

@description('Publisher for image definitions metadata.')
param publisher string = org
@description('Offer for image definitions metadata.')
param offer string = 'build-agents'
@description('Linux SKU label')
param linuxSku string = 'linux'
@description('Windows SKU label')
param windowsSku string = 'windows'

// Image Definitions (no versions — versions created by pipeline/AIB)
// Using supported API version (2023-07-03) instead of 2023-07-01 which failed in swedencentral
resource linuxImageDef 'Microsoft.Compute/galleries/images@2023-07-03' = {
  name: '${galleryName}/${linuxImageDefinitionName}'
  location: location
  tags: {
    env: env
    loc: loc
    suffix: uniqueSuffix
  }
  properties: {
    description: 'Linux Azure DevOps / GitHub runner base image.'
    osType: 'Linux'
    osState: 'Generalized'
    identifier: {
      publisher: publisher
      offer: offer
      sku: linuxSku
    }
    hyperVGeneration: 'V2'
    features: [
      {
        name: 'IsAcceleratedNetworkSupported'
        value: 'True'
      }
    ]
  }
}

// Using supported API version (2023-07-03)
resource windowsImageDef 'Microsoft.Compute/galleries/images@2023-07-03' = {
  name: '${galleryName}/${windowsImageDefinitionName}'
  location: location
  tags: {
    env: env
    loc: loc
    suffix: uniqueSuffix
  }
  properties: {
    description: 'Windows Azure DevOps / GitHub runner base image.'
    osType: 'Windows'
    osState: 'Generalized'
    identifier: {
      publisher: publisher
      offer: offer
      sku: windowsSku
    }
    hyperVGeneration: 'V2'
  }
}

output linuxImageDefinitionId string = linuxImageDef.id
output windowsImageDefinitionId string = windowsImageDef.id
