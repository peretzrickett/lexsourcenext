@description('Name of the App Service Plan')
param name string

@description('Location where the App Service Plan will be deployed')
param location string

@description('SKU configuration for the App Service Plan')
param sku object = {
  name: 'P1v2'
  tier: 'PremiumV2'
  size: '1'
}

@description('Indicates whether the App Service Plan is for Linux')
param isLinux bool = false

@description('Maximum number of instances for the App Service Plan')
param maximumElasticWorkerCount int = 10

@description('Tags to apply to the App Service Plan')
param tags object = {}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: name
  location: location
  sku: sku
  properties: {
    reserved: isLinux
    maximumElasticWorkerCount: maximumElasticWorkerCount
  }
  tags: tags
}

@description('The resource ID of the App Service Plan')
output id string = appServicePlan.id

@description('The name of the App Service Plan')
output name string = appServicePlan.name
