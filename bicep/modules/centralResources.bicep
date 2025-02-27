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
  { name: 'GatewaySubnet', addressPrefix: '10.0.3.0/26' }
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
    topology: 'hub'
  }
}

module privateDnsZone 'privateDnsZone.bicep' = {
  name: 'privateDnsZone'
  params: {
    clientNames: clientNames
    discriminator: discriminator
  }
  dependsOn: [
    centralVNet
  ]
}

// Deploy Azure Firewall with DNS and rules
module firewall 'firewall.bicep' = {
  name: 'firewall'
  params: {
    name: firewallName
    location: location
    subnetId: centralVNet.outputs.subnets[0].id
    dnsServers: ['168.63.129.16']
    enableDnsProxy: true
  }
  dependsOn: [
    centralVNet
  ]
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

// Deploy Route Table for OtherServices
resource routeTable 'Microsoft.Network/routeTables@2023-02-01' = {
  name: 'RouteTable'
  location: location
  properties: {
    routes: [
      {
        name: 'RouteToFirewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.outputs.privateIp
        }
      }
    ]
  }
  dependsOn: [
    centralVNet
  ]
}

resource parentVNet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-${discriminator}-Central'
  dependsOn: [
    centralVNet
  ]
}

// Associate Route Table with OtherServices subnet
resource otherServicesSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' = {
  name: 'OtherServices'
  parent: parentVNet
  properties: {
    addressPrefix: '10.0.2.0/24'
    routeTable: {
      id: routeTable.id
    }
  }
}
