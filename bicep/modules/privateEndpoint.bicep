@description('Name of the Private Endpoint')
param name string

@description('Location where the Private Endpoint will be deployed')
param location string

@description('ID of the target resource for the Private Link connection')
param privateLinkServiceId string

@description('Subnet ID where the Private Endpoint will be created')
param subnetId string

@description('Group ID(s) for the resource type (e.g., blob, sqlServer, vault, sites)')
param groupIds array

@description('Tags to apply to the Private Endpoint')
param tags object = {}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${name}'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
  tags: tags
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id
