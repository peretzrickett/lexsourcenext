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
  name: 'vnet${clientName}'
  params: {
    name: 'vnet${clientName}'
    location: location
    addressPrefixes: [cidr]
    subnets: [
      { name: 'FrontEnd', addressPrefix: subnets.frontEnd }
      { name: 'BackEnd', addressPrefix: subnets.backEnd }
    ]
  }
}

// Deploy App Service Plan
// module appServicePlan 'appServicePlan.bicep' = {
//   name: 'asp${clientName}'
//   params: {
//     name: 'asp${clientName}'
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
//   name: 'app${clientName}'
//   params: {
//     name: 'app${clientName}'
//     location: location
//     appServicePlanId: appServicePlan.outputs.id
//   }
// }

// Deploy SQL Server
module sqlServer 'sqlServer.bicep' = {
  name: 'sql${clientName}'
  params: {
    name: 'sql${clientName}'
    location: location
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!' // Replace with secure param later
  }
}

// Deploy Storage Account
module storageAccount 'storageAccount.bicep' = {
  name: 'stg${clientName}'
  params: {
    name: toLower('stg${clientName}')
    location: location
  }
}

// Deploy Key Vault
module keyVault 'keyVault.bicep' = {
  name: 'kv${clientName}'
  params: {
    name: 'kv${clientName}'
    location: location
  }
}

// Deploy App Insights
module appInsights 'appInsights.bicep' = {
  name: 'ai${clientName}'
  params: {
    name: 'ai${clientName}'
    location: location
  }
}
