// modules/vnetSpokePeering.bicep
param clientName string
param discriminator string

resource spokeVnet 'Microsoft.Network/virtualNetworks@2022-09-01' existing = {
  name: 'vnet-${discriminator}-${clientName}'
}

// // Extract the spoke VNet base name
// var hubVnetBaseName = last(split(centralVnetId, '-'))

// // Extract the spoke VNet resource group
// var hubVnetResourceGroup = split(centralVnetId, '/')[4] // Resource group name is at index 4

var hubVnetRg = 'rg-${discriminator}-central'
var hubVnetName = 'vnet-${discriminator}-Central'

resource spokeToHubPeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-09-01' = {
  name: '${spokeVnet.name}-to-${hubVnetName}'
  parent: spokeVnet
  properties: {
    remoteVirtualNetwork: {
      id: resourceId(hubVnetRg, 'Microsoft.Network/virtualNetworks', hubVnetName)
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
