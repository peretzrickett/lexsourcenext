@description('Name of the Application Insights instance')
param name string

@description('Location of the Application Insights instance')
param location string

@description('Subnet ID for Private Link')
param subnetId string

@description('Application type for Application Insights')
@allowed([
  'web'
  'other'
  'java'
  'node.js'
])
param applicationType string = 'web'

@description('Workspace resource ID for linking Application Insights to a Log Analytics workspace (optional)')
param workspaceResourceId string = ''

@description('Tags to apply to the Application Insights instance')
param tags object = {}

@description('Create an Application Insights instance')
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  kind: applicationType // Use the application type as the "kind"
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: empty(workspaceResourceId) ? null : workspaceResourceId
  }
  tags: tags
}

// Private Endpoint for App Insights
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: location
    privateLinkServiceId: appInsights.id
    subnetId: subnetId
    groupIds: [ 'components' ]
    tags: tags
  }
}

@description('The resource ID of the App Insights')
output id string = appInsights.id

@description('The instrumentation key of the App Insights')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string of the App Insights')
output connectionString string = appInsights.properties.ConnectionString
