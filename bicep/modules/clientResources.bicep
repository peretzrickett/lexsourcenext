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
module spokeVnet 'vnet.bicep' = {
  name: 'vnet-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    name: clientName
    location: location
    discriminator: discriminator
    addressPrefixes: [cidr]
    subnets: [
      { name: 'FrontEnd', addressPrefix: subnets.frontEnd }
      { name: 'BackEnd', addressPrefix: subnets.backEnd }
      { name: 'PrivateLink', addressPrefix: subnets.privateLink }
    ]
  }
}

// Deploy App Service Plan
module appServicePlan 'appServicePlan.bicep' = {
  name: 'asp-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
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
  scope: resourceGroup('rg-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
    location: location
    subnetId: spokeVnet.outputs.subnets[0].id
    appServicePlanId: appServicePlan.outputs.id
  }
}

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  scope: resourceGroup('rg-${clientName}')
  name: 'sql-${discriminator}-${clientName}'
  params: {
    clientName: clientName
    discriminator: discriminator
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${discriminator}${clientName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: 'pkv-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: 'pai-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${clientName}')
  params: {
    discriminator: discriminator
    enablePrivateLinkScope: true
    enablePrivateLink: true
    clientName: clientName
    location: location
    subnetId: spokeVnet.outputs.subnets[1].id
  }
}

