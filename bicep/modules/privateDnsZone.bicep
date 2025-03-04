// modules/privateDnsZone.bicep

@description('Names of the clients')
param clientNames array

@description('Distinguished qualifier for resources')
param discriminator string

@description('List of Private DNS Zones to create')
param privateDnsZonesMetadata array = [
  {zoneName: 'privatelink.azurewebsites.net', linkType: 'app'}          // App Service Private Link
  {zoneName: 'privatelink.${environment().suffixes.sqlServerHostname}', linkType: 'sql'}       // SQL, CosmosDB Private Link
  {zoneName: 'privatelink.monitor.azure.com', linkType: 'pai'}          // App Insights Private Link
  {zoneName: 'privatelink.vaultcore.azure.net', linkType: 'pkv'}        // Key Vault Private Link
  {zoneName: 'privatelink.blob.${environment().suffixes.storage}', linkType: 'stg'}      // Storage Blob
  {zoneName: 'privatelink.file.${environment().suffixes.storage}', linkType: 'stg'}      // Storage File Shares
  {zoneName: 'privatelink.insights.azure.com', linkType: 'pai'}
  {zoneName: 'privatelink.${environment().suffixes.storage}', linkType: 'stg'}
]

// Helper function to clean up DNS zone names if needed
var cleanedZones = [for zone in privateDnsZonesMetadata: {
  zoneName: replace(zone.zoneName, '..', '.')  // Remove any double periods
  linkType: zone.linkType
}]

// Use the central vnet for linking private dns zones
resource centralVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-${discriminator}-central'
}

// Create Private DNS Zones for spoke vnet if enabled
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for (zone, index) in cleanedZones: {
  name: zone.zoneName
  location: 'global'
}]

// Link Private DNS Zones to spoke VNet
resource privateDnsLinksToHub 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zone, index) in cleanedZones: {
  name: 'dnsl-${discriminator}-central-${privateDnsZones[index].name}'  // Unique name using loop index
  parent: privateDnsZones[index]  // Use the correct array index
  location: 'global'
  properties: {
    virtualNetwork: {
      id: centralVnet.id
    }
    registrationEnabled: false
  }
}]

// Create a single flattened array of all client-zone combinations
var dnsLinks = [for i in range(0, length(clientNames) * length(cleanedZones)): {
  clientName: clientNames[i / length(cleanedZones)]
  zone: cleanedZones[i % length(cleanedZones)]
}]

// Link Private DNS Zones to spoke VNets (in rg-central, single loop)
resource privateDnsLinksToSpoke 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for link in dnsLinks: {
  name: 'dnsl-${discriminator}-${link.clientName}-${link.zone.zoneName}'
  parent: privateDnsZones[indexOf(cleanedZones, link.zone)]
  location: 'global'
  properties: {
    virtualNetwork: {
      id: resourceId('rg-${link.clientName}', 'Microsoft.Network/virtualNetworks', 'vnet-${discriminator}-${link.clientName}')
    }
    registrationEnabled: false
  }
}]

// Deploy the script that creates the DNS records
@batchSize(3)
module createDnsRecords 'privateDnsRecord.bicep' = [for (zone, index) in cleanedZones: {
  name: 'createDnsRecords-${zone.zoneName}-${index}'
  params: {
    clientNames: clientNames
    discriminator: discriminator  
    privateDnsZoneName: zone.zoneName
    endpointType: zone.linkType
  }
  scope: resourceGroup()
  dependsOn: [
    privateDnsZones[index]
  ]
}]
