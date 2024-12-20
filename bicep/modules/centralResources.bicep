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
param distinguishedQualifier string

@description('Subnets for the central VNet')
param subnets array = [
  { name: 'AzureFirewallSubnet', addressPrefix: '10.0.1.0/24' }
  { name: 'OtherServices', addressPrefix: '10.0.2.0/24' }
]

// Deploy the central VNet
module centralVNet 'vnet.bicep' = {
  name: 'centralVNet'
  params: {
    name: 'vnet-${distinguishedQualifier}-Central'
    location: location
    addressPrefixes: [centralVNetCidr]
    subnets: subnets
  }
}

// Deploy Azure Front Door
module frontDoor 'frontDoor.bicep' = {
  name: 'frontDoor'
  params: {
    name: frontDoorName
  }
}

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
}
