targetScope = 'subscription'

@description('List of client configurations for deployment')
param clients array

@description('Location for all resources, defaults to East US')
param location string = 'eastus'

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string = 'lexsb'

// Create the central resource group at the subscription level
module centralResourceGroup 'modules/resourceGroup.bicep' = {
  name: 'centralResourceGroup'
  params: {
    name: 'rg-central'
    location: location
  }
}

// Create resource groups for each client at the subscription level
module clientResourceGroups 'modules/resourceGroup.bicep' = [for client in clients: {
  name: 'rg-${client.name}'
  params: {
    name: 'rg-${client.name}'
    location: location
  }
}]

// Deploy central resources
module centralResources 'modules/centralResources.bicep' = {
  name: 'centralResourcesDeployment'
  scope: resourceGroup('rg-central')
  params: {
    location: location
    discriminator: discriminator
    clientNames: [for client in clients: client.name] // Extract only client names for central resources
  }
  dependsOn: [
    centralResourceGroup
    clientResources
  ]
}

// Deploy client-specific resources
module clientResources 'modules/clientResources.bicep' = [for client in clients: {
  name: '${client.name}-resources'
  scope: resourceGroup('rg-${client.name}')
  params: {
    clientName: client.name
    location: location
    cidr: client.cidr
    subnets: client.subnets
    discriminator: discriminator
  }
  dependsOn: [
    clientResourceGroups
  ]
}]

module privateDnsZone 'modules/privateDnsZone.bicep' = {
  name: 'privateDnsZone'
  scope: resourceGroup('rg-central')
  params: {
    clientNames: [for client in clients: client.name]
    discriminator: discriminator
  }
  dependsOn: [
    centralResources
    clientResources
  ]
}

// Peer the central VNet with each client VNet
@batchSize(1)
module peering 'modules/vnetPeering.bicep' = [for client in clients: {
  name: 'vnetPeering-${client.name}'
  scope: subscription()
  params: {
    clientName: client.name
    discriminator: discriminator
  }
  dependsOn: [
    centralResources
    clientResources
    privateDnsZone
  ]
}] 

// Deploy Azure Front Door
module frontDoorConfiguration 'modules/frontDoorConfigure.bicep' = {
  name: 'frontDoorConfiguration'
  scope: resourceGroup('rg-central')
  params: {
    clientNames: [for client in clients: client.name] // Extract only client names for Front Door configuration
    name: 'globalFrontDoor'
    discriminator: discriminator
  }
  dependsOn: [
    peering
  ]
}

@description('Whether to deploy VPN Gateway as part of the deployment')
param deployVpn bool = true

@description('VPN certificate name for P2S VPN authentication')
param vpnRootCertName string = 'P2SRootCert'

@description('VPN certificate data for P2S VPN authentication (base64-encoded .cer file). If not provided, a certificate will be generated automatically.')
@secure()
param vpnRootCertData string = ''

// Deploy the managed identity in the central resource group if it doesn't exist
module deploymentScriptsIdentity 'modules/managedIdentity.bicep' = {
  name: 'deployment-scripts-identity'
  scope: resourceGroup('rg-central')
  params: {
    name: 'uami-deployment-scripts'
    location: location
  }
  dependsOn: [
    centralResourceGroup
  ]
}

// Create Key Vault directly in main.bicep to make sure it exists before VPN deployment
module centralKeyVault 'modules/centralKeyVault.bicep' = {
  name: 'central-key-vault-deployment'
  scope: resourceGroup('rg-central')
  params: {
    name: 'central'
    location: location
    discriminator: discriminator
    accessPolicies: [
      {
        objectId: deploymentScriptsIdentity.outputs.principalId
        tenantId: subscription().tenantId
        permissions: {
          certificates: ['all']
          secrets: ['all']
          keys: ['all']
        }
      }
    ]
    enableRbacAuthorization: false // Use access policies for clearer permissions
  }
  dependsOn: [
    centralResourceGroup
    deploymentScriptsIdentity
  ]
}

// Assign Key Vault Administrator role to the managed identity 
module kvRoleAssignment 'modules/keyVaultRoleAssignment.bicep' = {
  name: 'kv-role-assignment'
  scope: resourceGroup('rg-central')
  params: {
    principalId: deploymentScriptsIdentity.outputs.principalId
    keyVaultName: centralKeyVault.outputs.name
  }
  dependsOn: [
    centralKeyVault
  ]
}

// VPN module will use the Key Vault we created above

// Deploy VPN Gateway in the central resource group
module vpnGateway 'modules/vpn.bicep' = if (deployVpn) {
  name: 'vpnGatewayDeployment'
  scope: resourceGroup('rg-central')
  params: {
    discriminator: discriminator
    location: location
    addressPool: '172.16.0.0/24'
    authType: 'Certificate'
    rootCertData: vpnRootCertData
    rootCertName: vpnRootCertName
    uamiId: deploymentScriptsIdentity.outputs.uamiId
    keyVaultName: centralKeyVault.outputs.name
  }
  dependsOn: [
    centralResources
    frontDoorConfiguration
    centralKeyVault
    kvRoleAssignment
  ]
}

@description('VPN client package URL for connection')
output vpnClientPackageUrl string = deployVpn ? vpnGateway.outputs.vpnClientPackageUrl : ''
