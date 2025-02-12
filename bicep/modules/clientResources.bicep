@description('Client Name')
param clientName string

@description('Location for client resources')
param location string

@description('VNet CIDR block')
param cidr string

@description('Subnets configuration')
param subnets object

@description('Distinguished qualifier for resources')
param discriminator string

var resourceBaseName = '${discriminator}-${clientName}'

// Deploy VNet
module spokeVnet 'vnet.bicep' = {
  name: 'vnet-${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: 'vnet-${resourceBaseName}'
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
  name: 'asp-${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: 'asp-${resourceBaseName}'
    location: location
    sku: {
      name: 'S1'
      tier: 'Standard'
      size: 'S1'
      capacity: 1
    }
  }
}

// Deploy App Service
module appService 'appService.bicep' = {
  name: 'app-${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: 'app-${resourceBaseName}'
    location: location
    subnetId: spokeVnet.outputs.subnets[0].id
    appServicePlanId: appServicePlan.outputs.id
  }
}

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  scope: resourceGroup('rg-${clientName}')
  name: 'sql-${resourceBaseName}'
  params: {
    name: 'sql-${resourceBaseName}'
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: 'stg${resourceBaseName}'
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: 'pkv-${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: 'pkv-${resourceBaseName}'
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: 'pai-${resourceBaseName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    enablePrivateLinkScope: true
    enablePrivateLink: true
    name: resourceBaseName
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

