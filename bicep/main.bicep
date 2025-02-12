targetScope = 'subscription'

@description('List of client configurations')
param clients array

@description('Location for all resources')
param location string = 'eastus'

@description('Distinguished qualifier for resources')
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
    clients: clients
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

module peering 'modules/vnetPeering.bicep' = [for client in clients: {
  name: 'vnetPeering-${client.name}'
  scope: subscription()
  params: {
    clientName: client.name
    discriminator: discriminator
  }
  // params: {
  //   centralVnetId: resourceId('Microsoft.Network/virtualNetworks', 'vnet-${discriminator}-Central')
  //   spokeVnetId: resourceId('rg-${client.name}', 'Microsoft.Network/virtualNetworks', 'vnet-${discriminator}-${client.name}')
  // }
  dependsOn: [
    centralResources
    clientResources
  ]
}] 

