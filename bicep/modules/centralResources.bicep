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

@description('Subnets for the central VNet')
param subnets array = [
  { name: 'FirewallSubnet', addressPrefix: '10.0.1.0/24' }
  { name: 'OtherServices', addressPrefix: '10.0.2.0/24' }
]

// Deploy the central VNet
module centralVNet 'vnet.bicep' = {
  name: 'centralVNetDeployment'
  params: {
    name: 'central-vnet'
    location: location
    addressPrefixes: [centralVNetCidr]
    subnets: subnets
  }
}

// Deploy Azure Front Door
module frontDoor 'frontDoor.bicep' = {
  name: 'frontDoorDeployment'
  params: {
    location: location
    name: frontDoorName
  }
}

// Deploy Azure Firewall
module firewall 'firewall.bicep' = {
  name: 'firewallDeployment'
  params: {
    name: firewallName
    location: location
    subnetId: centralVNet.outputs.subnets[0].id
  }
}

// Deploy Sentinel (Log Analytics Workspace)
module sentinel 'sentinel.bicep' = {
  name: 'sentinelDeployment'
  params: {
    name: sentinelWorkspaceName
    location: location
  }
}