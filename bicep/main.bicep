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
