@description('Name of the App Service')
param name string

@description('Location where the App Service will be deployed')
param location string


@description('Subnet ID for Private Link')
param subnetId string

@description('ID of the App Service Plan')
param appServicePlanId string

@description('Runtime stack for the App Service (e.g., DOTNETCORE, NODE, JAVA)')
@allowed([
  'DOTNETCORE'
  'NODE'
  'JAVA'
  'PYTHON'
  'PHP'
])
param runtimeStack string = 'DOTNETCORE'

@description('Version of the runtime stack')
param runtimeVersion string = '7.0'

@description('Tags to apply to the App Service')
param tags object = {}

@description('Environment variables (App Settings) for the App Service')
param appSettings array = []

// Create the App Service resource
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: name
  location: location
  properties: {
    serverFarmId: appServicePlanId // Link to the App Service Plan
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      appSettings: [
        for setting in appSettings: {
          name: setting.name
          value: setting.value
        }
      ]
    }
  }
  tags: tags
}

// Private Endpoint for App Service
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: location
    privateLinkServiceId: appService.id
    subnetId: subnetId
    groupIds: [ 'sites' ]
    tags: tags
  }
}

// Output the resource ID of the App Service
@description('The resource ID of the App Service')
output id string = appService.id

// Output the default URL of the App Service
@description('The default URL of the App Service')
output defaultHostName string = appService.properties.defaultHostName

// Output the name of the App Service
@description('The name of the App Service')
output name string = appService.name
