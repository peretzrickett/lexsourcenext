// modules/clientResources.bicep

@description('Name of the client for resource deployment')
param clientName string

@description('Location for client-specific resources')
param location string

@description('CIDR block for the client VNet')
param cidr string

@description('Subnet configuration for the client VNet')
param subnets object

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

// Deploy VNet for the spoke network
module spokeVnet 'vnet.bicep' = {
  name: 'vnet-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  params: {
    name: clientName
    location: location
    discriminator: discriminator
    addressPrefixes: [cidr]
    topology: 'spoke'
    subnets: [
      { name: 'FrontEnd', addressPrefix: subnets.frontEnd }
      { name: 'BackEnd', addressPrefix: subnets.backEnd }
      { name: 'PrivateLink', addressPrefix: subnets.privateLink }
    ]
  }
}

// Deploy App Service Plan for the client
module appServicePlan 'appServicePlan.bicep' = {
  name: 'asp-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
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
  dependsOn: [
    spokeVnet
  ]
}

// Deploy App Service (use FrontEnd subnet for vnetIntegration, remove private endpoint)
module appService 'appService.bicep' = {
  name: 'app-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
    subnetId: spokeVnet.outputs.subnets[0].id // Use FrontEnd subnet (index 0) for vnetIntegration
    appServicePlanId: appServicePlan.outputs.id
  }
}

// Deploy SQL Server (keep private endpoint, uses PrivateLink subnet)
module sqlServer 'sqlServer.bicep' = {
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  name: 'sql-${discriminator}-${clientName}'
  params: {
    clientName: clientName
    discriminator: discriminator
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure parameter in production
  }
  dependsOn: [
    spokeVnet
  ]
}

// Deploy Storage Account (keep private endpoint, uses PrivateLink subnet)
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${discriminator}${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
  }
  dependsOn: [
    spokeVnet
  ]
}

// Deploy Key Vault (keep private endpoint, uses PrivateLink subnet)
module keyVault 'keyVault.bicep' = {
  name: 'pkv-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  params: {
    clientName: clientName
    discriminator: discriminator
  }
  dependsOn: [
    spokeVnet
  ]
}

// Deploy App Insights (keep private endpoint, uses PrivateLink subnet)
module appInsights 'appInsights.bicep' = {
  name: 'pai-${discriminator}-${clientName}'
  scope: resourceGroup('rg-${discriminator}-${clientName}')
  params: {
    discriminator: discriminator
    enablePrivateLinkScope: true
    enablePrivateLink: true
    clientName: clientName
  }
  dependsOn: [
    spokeVnet
  ]
}
