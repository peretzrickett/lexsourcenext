// param centralVnetId string
// param spokeVnetId string

param clientName string
param discriminator string

resource centralVnet 'Microsoft.Network/virtualNetworks@2022-09-01' existing = {
//  name: last(split(centralVnetId, '/'))
  name: 'vnet-${discriminator}-Central'
}

var spokeVnetName = 'vnet-${discriminator}-${clientName}'
// Extract the spoke VNet base name
//var spokeVnetBaseName = last(split(spokeVnetId, '-'))
var spokeVnetRg = 'rg-${clientName}'

// Extract the spoke VNet resource group
//var spokeVnetResourceGroup = split(spokeVnetId, '/')[4] // Resource group name is at index 4

resource hubToSpokePeerings 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-09-01' = {
  name: '${centralVnet.name}-to-${spokeVnetName}'
  parent: centralVnet
  properties: {
    remoteVirtualNetwork: {
      id: resourceId(spokeVnetRg, 'Microsoft.Network/virtualNetworks', spokeVnetName)
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}
