param name string
param location string
param subnetId string
param privateLinkServiceId string
param groupIds array

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-02-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-link'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: groupIds
        }
      }
    ]
  }
}

output id string = privateEndpoint.id
