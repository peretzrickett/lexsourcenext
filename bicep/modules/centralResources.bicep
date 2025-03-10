// modules/centralResources.bicep

@description('Geographic location for all central resources')
param location string

@description('Name of the global Azure Firewall resource')
param firewallName string = 'globalFirewall'

@description('Name of the global Azure Front Door resource')
param frontDoorName string = 'globalFrontDoor'

@description('Name of the global Sentinel (Log Analytics) workspace')
param sentinelWorkspaceName string = 'globalSentinelWorkspace'

@description('CIDR block for the central VNet')
param centralVNetCidr string = '10.0.0.0/16'

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('List of client names for linking to central resources')
param clientNames array

@description('Subnet configuration for the central VNet')
param subnets array = [
  { name: 'AzureFirewallSubnet', addressPrefix: '10.0.1.0/24' }
  { name: 'OtherServices', addressPrefix: '10.0.2.0/24' }
  { name: 'GatewaySubnet', addressPrefix: '10.0.3.0/26' }
]

// Deploy the central VNet
module centralVnet 'vnet.bicep' = {
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
    centralVnet
  ]
}

// Extract client private endpoint subnets for firewall rules
var clientPrivateLinkSubnets = [for client in clientNames: '10.${indexOf(clientNames, client) + 1}.3.0/24']

// Deploy Azure Firewall with DNS proxy for central network security
module firewall 'firewall.bicep' = {
  name: 'firewall'
  params: {
    name: firewallName
    location: location
    subnetId: centralVnet.outputs.subnets[0].id
    dnsServers: ['168.63.129.16']
    enableDnsProxy: true
    clientSubnets: clientPrivateLinkSubnets // Pass client private endpoint subnets
  }
}

// Deploy Sentinel (Log Analytics Workspace) for monitoring
module sentinel 'sentinel.bicep' = {
  name: 'sentinel'
  params: {
    name: sentinelWorkspaceName
    location: location
  }
  dependsOn: [
    centralVnet
  ]
}

module frontdoor 'frontDoor.bicep' = {
  name: 'frontDoor'
  params: {
    name: frontDoorName
  }
  dependsOn: [
    centralVnet
  ]
}

// Deploy Route Table for routing traffic through the firewall
// Note: We do NOT apply this to the GatewaySubnet to allow VPN traffic to bypass firewall
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
      {
        // Exclude VPN client address space from routing through firewall
        name: 'BypassVpnClient'
        properties: {
          addressPrefix: '172.16.0.0/24' // VPN client address space
          nextHopType: 'VirtualNetworkGateway'
        }
      }
      {
        // Specific route for Azure Front Door private link subnet
        name: 'RouteToFrontDoorPrivateLink'
        properties: {
          addressPrefix: '10.8.0.0/16'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewall.outputs.privateIp
        }
      }
    ]
  }
}

resource parentVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-${discriminator}-Central'
  dependsOn: [
    centralVnet
  ]
}

// Associate Route Table with OtherServices subnet for central traffic routing
resource otherServicesSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' = {
  name: 'OtherServices'
  parent: parentVnet
  properties: {
    addressPrefix: '10.0.2.0/24'
    routeTable: {
      id: routeTable.id
    }
  }
}
