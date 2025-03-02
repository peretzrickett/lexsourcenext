// modules/privateEndpoint.bicep

@description('Name of the Private Endpoint for the target resource')
param name string

@description('Resource ID of the target service for the Private Link connection')
param privateLinkServiceId string

@description('Client name associated with the Private Endpoint')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Group ID specifying the type of resource (e.g., blob, sqlServer, vault, insights)')
param groupId string

@description('Tags to apply to the Private Endpoint for organization and billing')
param tags object = {}

// Reference the existing virtual network in the spoke
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-02-01' existing = {
  name: 'vnet-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
}

// Reference the existing PrivateLink subnet in the spoke VNet
resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' existing = {
  name: 'privateLink'
  parent: existingVnet
}

// Create the Private Endpoint in the spoke VNet for non-App Service resources
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

@description('The resource ID of the deployed Private Endpoint')
output id string = privateEndpoint.id
