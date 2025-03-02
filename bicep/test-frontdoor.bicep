targetScope = 'subscription'

@description('List of client configurations for deployment')
param clients array

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string = 'lexsb'

// Reference the central resource group
resource centralResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  name: 'rg-central'
}

// Deploy Azure Front Door configuration
module frontDoorConfiguration 'modules/frontDoorConfigure.bicep' = {
  name: 'testFrontDoorConfiguration'
  scope: centralResourceGroup
  params: {
    clientNames: [for client in clients: client.name]
    name: 'globalFrontDoor'
    discriminator: discriminator
  }
}