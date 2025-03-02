// modules/vnet.bicep

@description('Creates a virtual network with the specified naming')
param name string

@description('Geographic location for all resources')
param location string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Address prefixes for the virtual network')
param addressPrefixes array

@description('Subnet configuration for the virtual network')
param subnets array

@description('Spoke or hub designation for VNet creation')
@allowed([
  'hub'
  'spoke'
])
param topology string

var vnetName = 'vnet-${discriminator}-${name}'

// Create the virtual network resource
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    subnets: [
      for (subnet, index) in subnets: {
        name: subnet.name
        properties: {
          privateEndpointNetworkPolicies: (topology == 'spoke') ? 'Disabled' : null
          privateLinkServiceNetworkPolicies: (topology == 'spoke') ? 'Disabled' : null
          addressPrefix: subnet.addressPrefix
          networkSecurityGroup: (topology == 'spoke') ? {
            id: nsg.outputs.nsgIds[index]
          } : null
          delegations: ((topology == 'spoke') && subnet.name == 'FrontEnd') ? [
            {
              name: 'MicrosoftWebServerFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ] : null
        }
      }
    ]
  }
}

module nsg 'nsg.bicep' = if (topology == 'spoke') {
  name: 'nsg-${discriminator}-${name}'
  params: {
    location: location
    clientName: name
    discriminator: discriminator
    frontDoorPrivateIp: '10.0.0.0/16'
  }
}

@description('The subnet IDs of the virtual network for connectivity and integration')
output subnets array = [
  for subnet in subnets: {
    name: subnet.name
    id: '${vnet.id}/subnets/${subnet.name}'
  }
]

@description('The resource ID of the virtual network for reference')
output vnetId string = vnet.id
