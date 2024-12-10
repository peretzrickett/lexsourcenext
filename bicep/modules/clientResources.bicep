@description('Client Name')
param clientName string

@description('Location for client resources')
param location string

@description('VNet CIDR block')
param cidr string

@description('Subnets configuration')
param subnets object

// Deploy VNet
module vnet 'vnet.bicep' = {
  name: '${clientName}-vnet'
  params: {
    name: '${clientName}-vnet'
    location: location
    addressPrefixes: [cidr]
    subnets: [
      { name: 'FrontEnd', addressPrefix: subnets.frontEnd }
      { name: 'BackEnd', addressPrefix: subnets.backEnd }
    ]
  }
}

// Deploy App Service Plan
module appServicePlan 'appServicePlan.bicep' = {
  name: '${clientName}-appServicePlan'
  params: {
    name: '${clientName}-appServicePlan'
    location: location
    sku: {
      name: 'P1v2'
      tier: 'PremiumV2'
      size: '1'
    }
  }
}

// Deploy App Service
module appService 'appService.bicep' = {
  name: '${clientName}-appService'
  params: {
    name: '${clientName}-appService'
    location: location
    appServicePlanId: appServicePlan.outputs.id
  }
}

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  name: '${clientName}-sqlServer'
  params: {
    name: '${clientName}-sql'
    location: location
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: '${clientName}-storage'
  params: {
    name: toLower('${clientName}storage')
    location: location
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: '${clientName}-keyVault'
  params: {
    name: '${clientName}-kv'
    location: location
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: '${clientName}-appInsights'
  params: {
    name: '${clientName}-ai'
    location: location
  }
}
