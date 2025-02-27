// modules/vnetPeering.bicep

targetScope = 'subscription'

// param centralVnetId string
// param spokeVnetId string
param clientName string
param discriminator string

// // Extract the spoke VNet resource group
// var hubVnetResourceGroup = split(spokeVnetId, '/')[4] // Resource group name is at index 4

// // Extract the spoke VNet resource group
// var spokeVnetResourceGroup = split(spokeVnetId, '/')[4] // Resource group name is at index 4

module hubPeering 'vnetHubPeering.bicep' = {
  name: 'hubPeering'
  scope: resourceGroup('rg-central')
  params: {
    // centralVnetId: centralVnetId
    // spokeVnetId: spokeVnetId
    clientName: clientName
    discriminator: discriminator
  }
}

module spokePeering 'vnetSpokePeering.bicep' = {
  name: 'spokePeering'
  scope: resourceGroup('rg-${clientName}')
  params: {
    // centralVnetId: centralVnetId
    // spokeVnetId: spokeVnetId
    clientName: clientName
    discriminator: discriminator
  }
}
