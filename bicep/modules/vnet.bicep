@description('Creates a virtual network with the specified name')
param name string

@description('Location for all resources')
param location string

@description('Address prefixes for the virtual network')
param addressPrefixes array

@description('Subnets for the virtual network')
param subnets array

@description('Enable Private DNS for this VNet')
param enablePrivateDns bool = true

@description('List of Private DNS Zones to create')
param privateDnsZoneNames array = [
  'privatelink.azurewebsites.net'          // App Service Private Link
  'privatelink${environment().suffixes.sqlServerHostname}'       // SQL, CosmosDB Private Link
  'privatelink.monitor.azure.com'          // App Insights Private Link
  'privatelink.vaultcore.azure.net'        // Key Vault Private Link
  'privatelink.blob.${environment().suffixes.storage}'      // Storage Blob
  'privatelink.file.${environment().suffixes.storage}'      // Storage File Shares
]

// Create the virtual network resource
resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    subnets: [
      for subnet in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
        }
      }
    ]
  }
}

// Create Private DNS Zones if enabled
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZoneNames: if (enablePrivateDns) {
  name: zoneName
  location: 'global'
}]

// Link Private DNS Zones to VNet
resource privateDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, index) in privateDnsZoneNames: if (enablePrivateDns) {
  name: 'dnsl-${name}-${index}'  // Unique name using loop index
  parent: privateDnsZones[index]  // Use the correct array index
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

@description('The subnet IDs of the virtual network')
output subnets array = [
  for subnet in subnets: {
    name: subnet.name
    id: '${vnet.id}/subnets/${subnet.name}'
  }
]

@description('The resource ID of the virtual network')
output vnetId string = vnet.id
