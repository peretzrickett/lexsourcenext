// main.bicep
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

// module managedIdentity 'modules/managedIdentity.bicep' = {
//   name: 'managedIdentity'
//   scope: resourceGroup('rg-central')
//   params: {
//     name: 'uami-deployment-scripts'
//   }
// }

// Create resource groups for each client at the subscription level
module clientResourceGroups 'modules/resourceGroup.bicep' = [for client in clients: {
  name: 'rg-${client.name}'
  params: {
    name: 'rg-${client.name}'
    location: location
  }
  // dependsOn: [
  //   managedIdentity
  // ]
}]

// Deploy central resources
module centralResources 'modules/centralResources.bicep' = {
  name: 'centralResourcesDeployment'
  scope: resourceGroup('rg-central')
  params: {
    location: location
    discriminator: discriminator
    clientNames: [for client in clients: client.name] // Extract only names
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
  ]
}] 

// Deploy Azure Front Door
module frontDoorConfiguration 'modules/frontDoorConfigure.bicep' = {
  name: 'frontDoorConfiguration'
  scope: resourceGroup('rg-central')
  params: {
    clientNames: [for client in clients: client.name] // Extract only names
    name: 'globalFrontDoor'
    discriminator: discriminator
  }
  dependsOn: [
    peering
  ]
}
