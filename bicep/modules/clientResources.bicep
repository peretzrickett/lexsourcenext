@description('Client Name')
param clientName string

@description('Location for client resources')
param location string

@description('VNet CIDR block')
param cidr string

@description('Subnets configuration')
param subnets object

@description('Distinguished qualifier for resources')
param distinguishedQualifier string

// Deploy VNet
module vnet 'vnet.bicep' = {
  name: 'vnet-${distinguishedQualifier}-${clientName}'
  params: {
    name: 'vnet-${distinguishedQualifier}-${clientName}'
    location: location
    addressPrefixes: [cidr]
    subnets: [
      { name: 'FrontEnd', addressPrefix: subnets.frontEnd }
      { name: 'BackEnd', addressPrefix: subnets.backEnd }
    ]
  }
}

// // Deploy App Service Plan
// module appServicePlan 'appServicePlan.bicep' = {
//   name: 'asp-${distinguishedQualifier}-${clientName}'
//   params: {
//     name: 'asp-${distinguishedQualifier}-${clientName}'
//     location: location
//     sku: {
//       name: 'S1'
//       tier: 'Standard'
//       size: 'S1'
//       capacity: 1
//     }
//   }
// }

// // Deploy App Service
// module appService 'appService.bicep' = {
//   name: 'app-${distinguishedQualifier}-${clientName}'
//   params: {
//     name: 'app-${distinguishedQualifier}-${clientName}'
//     location: location
//     subnetId: vnet.outputs.subnets[0].id
//     appServicePlanId: appServicePlan.outputs.id
//   }
// }

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  name: 'sql-${distinguishedQualifier}-${clientName}'
  params: {
    name: 'sql-${distinguishedQualifier}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${distinguishedQualifier}${clientName}'
  params: {
    name: toLower('stg${clientName}')
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: 'pkv-${distinguishedQualifier}-${clientName}'
  params: {
    name: 'pkv-${distinguishedQualifier}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: 'pai-${distinguishedQualifier}-${clientName}'
  params: {
    name: 'ai-${distinguishedQualifier}-${clientName}'
    location: location
    subnetId: vnet.outputs.subnets[1].id
  }
}
