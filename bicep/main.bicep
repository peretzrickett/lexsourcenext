@description('List of client configurations')
param clients array

@description('Location for all resources')
param location string = 'eastus'

@description('Central Resource Group Name')
param centralResourceGroupName string = 'rg-central'

// Deploy Centralized Resources (Sentinel, Front Door, Firewall)
module centralResources 'modules/centralResources.bicep' = {
  name: 'centralResourcesDeployment'
  scope: resourceGroup(centralResourceGroupName)
  params: {
    location: location
  }
}

// Loop through each client and deploy their resources in their respective resource groups
module clientResources 'modules/clientResources.bicep' = [for client in clients: {
  name: '${client.name}-resources'
  scope: resourceGroup('rg-${client.name}')
  params: {
    clientName: client.name
    location: location
    cidr: client.cidr
    subnets: client.subnets
  }
}]
