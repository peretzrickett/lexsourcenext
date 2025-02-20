@description('Name of the Private Endpoint')
param name string

@description('Location where the Private Endpoint will be deployed')
param location string

@description('ID of the target resource for the Private Link connection')
param privateLinkServiceId string

@description('Client name for the Private Endpoint')
param clientName string

@description('Discriminator for the Private Endpoint')
param discriminator string

@description('Subnet ID where the Private Endpoint will be created')
param subnetId string

@description('Group ID(s) for the resource type (e.g., blob, sqlServer, vault, sites)')
param groupId string

@description('Private DNS Zone Name (e.g., privatelink.azurewebsites.net)')
param privateDnsZoneName string

@description('Tags to apply to the Private Endpoint')
param tags object = {}

// Create the Private Endpoint resource
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
          groupIds: [groupId]
        }
      }
    ]
  }
  tags: tags
}

// Retrieve the Private DNS Zone resource
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
}

// Get the private IP address of the Private Endpoint
module privateIpExtractor 'vnetIpExtractor.bicep' = {
  name: 'extractPrivateIp-${name}'
  scope: resourceGroup('rg-central')
  params: {
    name: name
    privateEndpointId: privateEndpoint.id
  }
}

// Create the Private DNS A Record resource
resource privateDnsARecord 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  name: 'a-${name}'
  parent: privateDnsZone
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: privateIpExtractor.outputs.privateIp
      }
    ]
  }
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id
