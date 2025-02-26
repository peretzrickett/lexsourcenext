// modules/privateEndpoint.bicep
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

@description('Group ID(s) for the resource type (e.g., blob, sqlServer, vault, sites, insights)')
param groupId string

@description('Private DNS Zone Name (e.g., privatelink.azurewebsites.net, privatelink.monitor.azure.com)')
param privateDnsZoneName string = 'privatelink.azurewebsites.net'

@description('Tags to apply to the Private Endpoint')
param tags object = {}

@description('Timeout for the deployment script in seconds')
param timeout int = 120

@description('Type of service for additional DNS configuration (e.g., "AppService", "AppInsights", "LogAnalytics", "KeyVault", "SqlServer", "Storage")')
@allowed([
  'AppService'
  'AppInsights'
  'LogAnalytics'
  'KeyVault'
  'SqlServer'
  'Storage'
])
param serviceType string

@description('Region for the service, if applicable (e.g., "eastus")')
param region string = 'eastus'

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
  location: location
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

// Retrieve the Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
}

// Extract Private IP and FQDN
module privateIpExtractor 'vnetIpExtractor.bicep' = {
  name: 'extractPrivateIp-${name}'
  scope: resourceGroup('rg-central')
  params: {
    name: name
    privateEndpointId: privateEndpoint.id
    timeout: timeout
    serviceType: serviceType
    clientName: clientName
    discriminator: discriminator
    region: region
  }
}

// Deploy the script that creates the DNS records
module createDnsRecords 'privateDnsRecord.bicep' = {
  name: 'createDnsRecords-${name}'
  params: {
    name: name
    privateDnsZoneName: privateDnsZoneName
    privateIps: privateIpExtractor.outputs.privateIps
    privateFqdns: privateIpExtractor.outputs.privateFqdns
  }
  scope: resourceGroup()
  dependsOn: [
    privateDnsZone
  ]
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id

@description('The private IP addresses of the Private Endpoint')
output privateIps array = privateIpExtractor.outputs.privateIps

@description('The private FQDNs of the Private Endpoint')
output privateFqdns array = privateIpExtractor.outputs.privateFqdns
