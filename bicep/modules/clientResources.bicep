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

// Deploy VNet
module vnet 'vnet.bicep' = {
  name: 'vnet-${discriminator}-${clientName}'
  params: {
    name: 'vnet-${discriminator}-${clientName}'
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
  name: 'asp-${discriminator}-${clientName}'
  params: {
    name: 'asp-${discriminator}-${clientName}'
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
  name: 'app-${discriminator}-${clientName}'
  params: {
    name: 'app-${discriminator}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[0].id
    appServicePlanId: appServicePlan.outputs.id
  }
}

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  name: 'sql-${discriminator}-${clientName}'
  params: {
    name: 'sql-${discriminator}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${discriminator}${clientName}'
  params: {
    name: toLower('stg${discriminator}${clientName}')
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: 'pkv-${discriminator}-${clientName}'
  params: {
    name: 'pkv-${discriminator}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: 'pai-${discriminator}-${clientName}'
  params: {
    name: 'ai-${discriminator}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}
