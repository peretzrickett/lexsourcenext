// modules/privateEndpoint.bicep

@description('Name of the Private Endpoint')
param name string

@description('ID of the target resource for the Private Link connection')
param privateLinkServiceId string

@description('Client name for the Private Endpoint')
param clientName string

@description('Discriminator for the Private Endpoint')
param discriminator string

@description('Group ID(s) for the resource type (e.g., blob, sqlServer, vault, sites, insights)')
param groupId string

@description('Tags to apply to the Private Endpoint')
param tags object = {}

// Reference an existing virtual network
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-02-01' existing = {
  name: 'vnet-${discriminator}-${clientName}'
}

// Reference an existing subnet
resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' existing = {
  name: 'privateLink'
  parent: existingVnet
}

// Create the Private Endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: resourceGroup().location
  properties: {
    subnet: {
      id: existingSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${name}'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [groupId]
        }
      }
    ]
  }
  tags: tags
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id
