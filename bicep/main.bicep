@description('List of client configurations')
param clients array

@description('Location for all resources')
param location string = 'eastus'

module frontDoor 'modules/frontDoor.bicep' = {
  name: 'frontDoorDeployment'
  params: {
    location: location
  }
}

module firewall 'modules/firewall.bicep' = {
  name: 'firewallDeployment'
  params: {
    name: 'globalFirewall'
    location: location
  }
}

module sentinel 'modules/sentinel.bicep' = {
  name: 'sentinelDeployment'
  params: {
    location: location
  }
}

// Loop through clients to deploy resources for each
var clientResources = [for client in clients: {
  vnet: {
    name: '${client.name}-vnet'
    cidr: client.cidr
    subnets: [
      { name: 'FrontEnd'; addressPrefix: client.subnets.frontEnd }
      { name: 'BackEnd'; addressPrefix: client.subnets.backEnd }
    ]
  }
  appServicePlan: {
    name: '${client.name}-appServicePlan'
  }
  appService: {
    name: '${client.name}-appService'
  }
  sqlServer: {
    name: '${client.name}-sql'
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!'
  }
  storageAccount: {
    name: '${client.name}storage'.toLower()
  }
  keyVault: {
    name: '${client.name}-kv'
  }
  appInsights: {
    name: '${client.name}-ai'
  }
}]

// Deploy each client's resources
resource deployments 'Microsoft.Resources/deployments@2021-04-01' = [for resource in clientResources: {
  name: '${resource.vnet.name}-deployment'
  template: {
    // Deploy VNet
    module vnet 'modules/vnet.bicep' = {
      name: '${resource.vnet.name}'
      params: {
        name: resource.vnet.name
        location: location
        addressPrefixes: [resource.vnet.cidr]
        subnets: resource.vnet.subnets
      }
    }

    // Deploy App Service Plan
    module appServicePlan 'modules/appServicePlan.bicep' = {
      name: '${resource.appServicePlan.name}'
      params: {
        name: resource.appServicePlan.name
        location: location
        sku: {
          name: 'P1v2'
          tier: 'PremiumV2'
          size: '1'
        }
      }
    }

    // Deploy App Service
    module appService 'modules/appService.bicep' = {
      name: '${resource.appService.name}'
      params: {
        name: resource.appService.name
        location: location
        appServicePlanId: appServicePlan.outputs.id
      }
    }

    // Deploy SQL Server
    module sqlServer 'modules/sqlServer.bicep' = {
      name: '${resource.sqlServer.name}'
      params: {
        name: resource.sqlServer.name
        location: location
        adminLogin: resource.sqlServer.adminLogin
        adminPassword: resource.sqlServer.adminPassword
      }
    }

    // Deploy Storage Account
    module storageAccount 'modules/storageAccount.bicep' = {
      name: '${resource.storageAccount.name}'
      params: {
        name: resource.storageAccount.name
        location: location
      }
    }

    // Deploy Key Vault
    module keyVault 'modules/keyVault.bicep' = {
      name: '${resource.keyVault.name}'
      params: {
        name: resource.keyVault.name
        location: location
      }
    }

    // Deploy App Insights
    module appInsights 'modules/appInsights.bicep' = {
      name: '${resource.appInsights.name}'
      params: {
        name: resource.appInsights.name
        location: location
      }
    }
  }
}]
