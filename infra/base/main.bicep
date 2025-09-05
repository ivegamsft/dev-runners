@description('Short org identifier (lowercase, alphanumeric).')
param org string
@description('Environment code, e.g. dev, test, prod.')
param env string
@description('Azure region for deployment.')
param location string = resourceGroup().location
@description('Short region code used in names (e.g. weu, use).')
param loc string
@description('Random unique suffix (3-6 chars) to ensure global uniqueness for KV / gallery).')
@minLength(3)
@maxLength(12)
param uniqueSuffix string

@description('Admin username for VMs (stored also as secret).')
param adminUsername string
@description('SSH public key for Linux agents (e.g. ssh-ed25519 or ssh-rsa). Password auth disabled when provided.')
param adminSshPublicKey string
@description('Temporarily allow password auth for Linux agents (fallback if SSH key validation fails).')
param linuxUsePassword bool = false

@description('SKU for Linux agents.')
param linuxVmSize string = 'Standard_D4s_v5'
@description('SKU for Windows agents.')
param windowsVmSize string = 'Standard_D4s_v5'

@description('Enable public IP for GitHub runner VM (not recommended for prod).')
param enableGhPublicIp bool = false


@description('Key Vault SKU')
@allowed([ 'standard', 'premium' ])
param keyVaultSku string = 'standard'

@description('Virtual network address space.')
param vnetAddressSpace string = '10.20.0.0/16'
@description('Subnet CIDR for agents.')
param subnetAgentsCidr string = '10.20.1.0/24'

@description('Existing image definition name for Linux agent (created by image deployment).')
param linuxImageDefinitionName string = 'linux-agent'
@description('Existing image definition name for Windows agent.')
param windowsImageDefinitionName string = 'windows-agent'

@description('Set true to use gallery image versions (they must exist). False uses marketplace images for initial bootstrap.')
param useGalleryImages bool = false

@description('Optional: Client ID of GitHub OIDC federated application (for reference/output only).')
@maxLength(64)
param githubOidcClientId string = ''

@description('Create compute gallery (set false temporarily if subscription lacks required features).')
param createGallery bool = true

@description('Marketplace publisher for Linux image fallback.')
param linuxImagePublisher string = 'Canonical'
@description('Marketplace offer for Linux image fallback.')
param linuxImageOffer string = '0001-com-ubuntu-server-jammy'
@description('Marketplace SKU for Linux image fallback.')
param linuxImageSku string = '22_04-lts'

@description('Marketplace publisher for Windows image fallback.')
param windowsImagePublisher string = 'MicrosoftWindowsServer'
@description('Marketplace offer for Windows image fallback.')
param windowsImageOffer string = 'WindowsServer'
@description('Marketplace SKU for Windows image fallback.')
param windowsImageSku string = '2022-datacenter-azure-edition'

// Key Vault name: must be 3-24 alphanumeric (no hyphens). Remove separators to comply.
var kvName = toLower('kv${org}${env}${loc}${uniqueSuffix}')
var galleryName = toLower('gal${org}${env}${loc}${uniqueSuffix}')
var vmssName = toLower('vmss-${org}-${env}-ado-${loc}')
var ghVmName = toLower('vm-${org}-${env}-gh-${loc}')
// Removed script storage (no longer needed)
// Windows computer name (NetBIOS) max 15 chars; derive truncated safe version.
var ghComputerName = toLower(substring(ghVmName, 0, min(length(ghVmName), 15)))
var vnetName = toLower('vnet-${org}-${env}-${loc}')
var subnetAgentsName = 'agents'
var linuxIdResName = toLower('id-${org}-${env}-lin-agents')
var winIdResName = toLower('id-${org}-${env}-win-agents')
var ghIdResName = toLower('id-${org}-${env}-gh-runner')
// Standard tags applied to most resources.
var standardTags = {
  org: org
  env: env
  loc: loc
  system: 'build-agents'
}
// Role definition IDs
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
// Removed Secrets Officer role id (not used)
// Removed deploy identity (no deployment script now).

// Resource Group scope assumed.

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: standardTags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      name: keyVaultSku
      family: 'A'
    }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'
  }
}

resource kvSecretAdminUsername 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'admin-username'
  parent: kv
  properties: {
    value: adminUsername
  }
}

resource gallery 'Microsoft.Compute/galleries@2025-03-03' = if (createGallery) {
  name: galleryName
  location: location
  tags: standardTags
  properties: {
    description: 'Compute Gallery for build agent images.'
    sharingProfile: {
      permissions: 'Private'
    }
    // Replication/target regions handled at image version level
  }
}

// Storage account for deployment script outputs (shared key access enabled to satisfy deploymentScripts execution)
// Removed storage account previously used for deployment script.

// Managed identities
resource linuxAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: linuxIdResName
  location: location
  tags: standardTags
}
resource windowsAgentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: winIdResName
  location: location
  tags: standardTags
}
resource ghRunnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: ghIdResName
  location: location
  tags: standardTags
}
// Removed deploy identity.

// Networking
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: standardTags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressSpace ]
    }
    subnets: [
      {
        name: subnetAgentsName
        properties: {
          addressPrefix: subnetAgentsCidr
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// Placeholders for image references (latest version). The version selection could be handled externally by orchestration.
@description('Linux agent image reference (gallery).')
param linuxImageVersion string = 'latest'
@description('Windows agent image reference (gallery).')
param windowsImageVersion string = 'latest'

// Image resource IDs expected: /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/galleries/<gallery>/images/<imageDefinition>/versions/<ver>
var linuxImageId = resourceId('Microsoft.Compute/galleries/images/versions', galleryName, linuxImageDefinitionName, linuxImageVersion)
var windowsImageId = resourceId('Microsoft.Compute/galleries/images/versions', galleryName, windowsImageDefinitionName, windowsImageVersion)

// Conditional image references: gallery version if requested, else marketplace latest
var linuxImageReference = useGalleryImages ? {
  id: linuxImageId
} : {
  publisher: linuxImagePublisher
  offer: linuxImageOffer
  sku: linuxImageSku
  version: 'latest'
}
var windowsImageReference = useGalleryImages ? {
  id: windowsImageId
} : {
  publisher: windowsImagePublisher
  offer: windowsImageOffer
  sku: windowsImageSku
  version: 'latest'
}

// VMSS for Azure DevOps agents (Linux example). For mix OS you could define two VMSS or multi image strategy.
resource vmssAdo 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: vmssName
  location: location
  tags: standardTags
  sku: {
    name: linuxVmSize
    capacity: 2
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${linuxAgentIdentity.id}': {}
    }
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          // Use gallery version or marketplace fallback
          ...linuxImageReference
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          caching: 'ReadWrite'
        }
      }
      osProfile: {
        computerNamePrefix: 'adoagent'
        adminUsername: adminUsername
        // Provide an admin password only when password auth is enabled
        ...(linuxUsePassword ? {
          adminPassword: empty(adminPassword) ? fallbackAdminPassword : adminPassword
        } : {})
        linuxConfiguration: linuxUsePassword ? {
          disablePasswordAuthentication: false
        } : {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: adminSshPublicKey
              }
            ]
          }
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nicConfig'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig'
                  properties: {
                    subnet: { id: '${vnet.id}/subnets/${subnetAgentsName}' }
                    primary: true
                    privateIPAddressVersion: 'IPv4'
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}

// Optional public IP for GitHub runner
resource ghPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (enableGhPublicIp) {
  name: '${ghVmName}-pip'
  location: location
  tags: standardTags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// NIC for GitHub runner VM
resource ghNic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: '${ghVmName}-nic'
  location: location
  tags: standardTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: '${vnet.id}/subnets/${subnetAgentsName}' }
          privateIPAddressVersion: 'IPv4'
          publicIPAddress: enableGhPublicIp ? { id: ghPublicIp.id } : null
        }
      }
    ]
  }
}

resource ghVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: ghVmName
  location: location
  tags: standardTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${ghRunnerIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: { vmSize: windowsVmSize }
    storageProfile: {
      imageReference: windowsImageReference
      osDisk: {
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    osProfile: {
      computerName: ghComputerName
      adminUsername: adminUsername
  adminPassword: empty(adminPassword) ? fallbackAdminPassword : adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
      }
      customData: base64('<powershell>Write-Host "Bootstrap GitHub runner; script will pull secrets from Key Vault via managed identity"</powershell>')
    }
    networkProfile: {
      networkInterfaces: [ { id: ghNic.id } ]
    }
  }
}

// Key Vault RBAC role assignments (Secrets User) for identities
resource kvRoleLinux 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, linuxAgentIdentity.id, 'kv-secrets')
  scope: kv
  properties: {
    principalId: linuxAgentIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
resource kvRoleWindows 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, windowsAgentIdentity.id, 'kv-secrets')
  scope: kv
  properties: {
    principalId: windowsAgentIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
resource kvRoleGh 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, ghRunnerIdentity.id, 'kv-secrets')
  scope: kv
  properties: {
    principalId: ghRunnerIdentity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}
// Removed deployment role assignment (Secrets Officer) no longer needed.

// Deployment script to generate password secret
// Deterministic password (bootstrap only). Replace/rotate after first deployment.
var pwSeg1 = toLower(substring(uniqueString(resourceGroup().id, uniqueSuffix), 0, 6))
var pwSeg2 = toUpper(substring(uniqueString(subscription().id, location), 0, 4))
var pwSeg3 = substring(replace(guid(resourceGroup().id, uniqueSuffix), '-', ''), 0, 6)
@secure()
@description('Admin password for Windows VM (supply via parameters file or Key Vault ref).')
param adminPassword string

// Fallback generation if adminPassword not supplied (not used when parameter provided)
var fallbackAdminPassword = '${pwSeg2}!${pwSeg1}${pwSeg3}Aa1!'

// Optionally create admin password secret if provided
resource kvSecretAdminPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(adminPassword)) {
  name: 'admin-password'
  parent: kv
  properties: { value: adminPassword }
}

@description('Outputs')
output keyVaultName string = kv.name
// Outputs
output vmssNameOut string = vmssAdo.name
output ghVmNameOut string = ghVm.name
output githubOidcClientIdOut string = githubOidcClientId
