// modules/appServicePlan.bicep

@description('Name of the App Service Plan for the client application')
param name string

@description('Geographic location where the App Service Plan will be deployed')
param location string

@description('SKU configuration defining the performance tier for the App Service Plan')
param sku object = {
  name: 'S1'
  tier: 'Standard'
  size: 'S1'
  capacity: 2
}

@description('Indicates whether the App Service Plan is configured for Linux, defaults to false')
param isLinux bool = false

@description('Maximum number of instances allowed for the App Service Plan for scalability')
param maximumElasticWorkerCount int = 10

@description('Tags for organizing and billing the App Service Plan')
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

@description('The resource ID of the deployed App Service Plan')
output id string = appServicePlan.id

@description('The name of the App Service Plan for reference')
output name string = appServicePlan.name
