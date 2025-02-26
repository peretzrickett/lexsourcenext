// modules/centralResources.bicep
@description('Location for all resources')
param location string

@description('Global Firewall Name')
param firewallName string = 'globalFirewall'

@description('Global Front Door Name')
param frontDoorName string = 'globalFrontDoor'

@description('Global Sentinel Workspace Name')
param sentinelWorkspaceName string = 'globalSentinelWorkspace'

@description('CIDR block for the central VNet')
param centralVNetCidr string = '10.0.0.0/16'

@description('Distinguished qualifier for resources')
param discriminator string

@description('Client Names')
param clientNames array

@description('Subnets for the central VNet')
param subnets array = [
  { name: 'AzureFirewallSubnet', addressPrefix: '10.0.1.0/24' }
  { name: 'OtherServices', addressPrefix: '10.0.2.0/24' }
  { name: 'GatewaySubnet', addressPrefix: '10.0.3.0/26'}
]

// Deploy the central VNet
module centralVNet 'vnet.bicep' = {
  name: 'centralVNet'
  params: {
    name: 'Central'
    location: location
    discriminator: discriminator
    addressPrefixes: [centralVNetCidr]
    subnets: subnets
    enableSpokePrivateDns: false
    enableHubPrivateDns: true
  }
}

// Retrieve the Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: 'privatelink.azurewebsites.net'
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: {
  name: 'pe-app-${discriminator}-${name}'
  scope: resourceGroup('rg-${name}')
}]

// Extract Private IP and FQDN
module privateIpExtractor 'vnetIpExtractor.bicep' = [ for (name, index) in clientNames: {
  name: 'extractPrivateIpFromSpoke-${name}'
  scope: resourceGroup('rg-${name}')
  params: {
    name: 'pe-app-${discriminator}-${name}'
    privateEndpointId: privateEndpoint[index].id
    timeout: 300
    serviceType: 'AppService'
    clientName: name
    discriminator: discriminator
    region: location
  }
}]

// Deploy the script that creates the DNS records
module createDnsRecords 'privateDnsRecord.bicep' = [ for (name, index) in clientNames: {
  name: 'createDnsRecords-${privateEndpoint[index].name}'
  params: {
    name: name
    privateDnsZoneName: privateDnsZone.name
    privateIps: privateIpExtractor[index].outputs.privateIps
    privateFqdns: privateIpExtractor[index].outputs.privateFqdns
  }
  scope: resourceGroup()
  dependsOn: [
    privateDnsZone
    privateEndpoint[index]
  ]
}]

// Deploy Azure Firewall
module firewall 'firewall.bicep' = {
  name: 'firewall'
  params: {
    name: firewallName
    location: location
    subnetId: centralVNet.outputs.subnets[0].id
  }
}

// Deploy Sentinel (Log Analytics Workspace)
module sentinel 'sentinel.bicep' = {
  name: 'sentinel'
  params: {
    name: sentinelWorkspaceName
    location: location
  }
  dependsOn: [
    centralVNet
  ]
}

module frontdoor 'frontDoor.bicep' = {
  name: 'frontDoor'
  params: {
    name: frontDoorName
  }
  dependsOn: [
    centralVNet
  ]
}

// module vpn 'vpn.bicep' = {
//   name: 'vpn'
//   params: {
//     location: location
//     discriminator: discriminator
//     addressPool: '10.0.255.0/24'
//   }
//   dependsOn: [
//     centralVNet
//   ]
// }
