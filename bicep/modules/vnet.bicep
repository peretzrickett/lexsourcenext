// modules/vnet.bicep
@description('Creates a virtual network with the specified name')
param name string

@description('Location for all resources')
param location string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Address prefixes for the virtual network')
param addressPrefixes array

@description('Subnets for the virtual network')
param subnets array

@description('Enable Private DNS for this VNet')
param enableSpokePrivateDns bool

@description('Enable Hub Private DNS for this VNet')
param enableHubPrivateDns bool

@description('List of Private DNS Zones to create')
param privateDnsZoneNames array = [
  'privatelink.azurewebsites.net'          // App Service Private Link
  'privatelink${environment().suffixes.sqlServerHostname}'       // SQL, CosmosDB Private Link
  'privatelink.monitor.azure.com'          // App Insights Private Link
  'privatelink.vaultcore.azure.net'        // Key Vault Private Link
  'privatelink.blob.${environment().suffixes.storage}'      // Storage Blob
  'privatelink.file.${environment().suffixes.storage}'      // Storage File Shares
  'privatelink.insights.azure.com'
  'privatelink.${environment().suffixes.storage}'
]

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
          privateEndpointNetworkPolicies: enableSpokePrivateDns ? 'Disabled' : null
          privateLinkServiceNetworkPolicies: enableSpokePrivateDns ? 'Disabled' : null
          addressPrefix: subnet.addressPrefix
          networkSecurityGroup: enableSpokePrivateDns ? {
            id: nsg.outputs.nsgIds[index]
          } : null
          delegations: (enableSpokePrivateDns && subnet.name == 'FrontEnd') ? [
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

// Create Private DNS Zones for spoke vnet if enabled
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for zoneName in privateDnsZoneNames: if (enableSpokePrivateDns) {
  name: zoneName
  location: 'global'
}]

// Link Private DNS Zones to spoke VNet
resource privateDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for (zoneName, index) in privateDnsZoneNames: if (enableSpokePrivateDns) {
  name: 'dnsl-${vnetName}-${index}'  // Unique name using loop index
  parent: privateDnsZones[index]  // Use the correct array index
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}]

// Create Private DNS Zone for web app on hub vnet if enabled
resource privateDnsZoneWebApp 'Microsoft.Network/privateDnsZones@2020-06-01' = if (enableHubPrivateDns) {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

// Link Private DNS Zone to hub VNet
resource privateDnsLinkWebApp 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (enableHubPrivateDns) {
  name: 'dnsl-${vnetName}-webapp'
  parent: privateDnsZoneWebApp
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

module nsg 'nsg.bicep' = if (enableSpokePrivateDns) {
  name: 'nsg-${discriminator}-${name}'
  params: {
    location: location
    clientName: name
    discriminator: discriminator
    frontDoorPrivateIp: '10.0.0.0/16'
  }
}


@description('The subnet IDs of the virtual network')
output subnets array = [
  for subnet in subnets: {
    name: subnet.name
    id: '${vnet.id}/subnets/${subnet.name}'
  }
]

@description('The resource ID of the virtual network')
output vnetId string = vnet.id
