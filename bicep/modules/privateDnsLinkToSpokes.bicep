@description('Distinguished qualifier for resources')
param discriminator string

@description('Name of the current client resource')
param clientName string

@description('List of Private DNS Zones to create')
param privateDnsZonesMetadata array = [
  {zoneName: 'privatelink.azurewebsites.net', linkType: 'app'}          // App Service Private Link
  {zoneName: 'privatelink${environment().suffixes.sqlServerHostname}', linkType: 'sql'}       // SQL, CosmosDB Private Link
  {zoneName: 'privatelink.monitor.azure.com', linkType: 'pai'}          // App Insights Private Link
  {zoneName: 'privatelink.vaultcore.azure.net', linkType: 'pkv'}        // Key Vault Private Link
  {zoneName: 'privatelink.blob.${environment().suffixes.storage}', linkType: 'stg'}      // Storage Blob
  {zoneName: 'privatelink.file.${environment().suffixes.storage}', linkType: 'stg'}      // Storage File Shares
  {zoneName: 'privatelink.insights.azure.com', linkType: 'pai'}
  {zoneName: 'privatelink.${environment().suffixes.storage}', linkType: 'stg'}
]

var privateDnsZoneNames = [for metadata in privateDnsZonesMetadata: metadata.zoneName]

// Use the central vnet for linking private dns zones
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
}

// Create Private DNS Zones for spoke vnet if enabled
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
}]


resource privateDnsLinksToSpoke 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, index) in privateDnsZoneNames: {
  name: 'dnsl-${discriminator}-${clientName}-${privateDnsZones[index].name}'  // Unique name using loop index
  parent: privateDnsZones[index]  // Use the correct array index
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: true
  }
}]
