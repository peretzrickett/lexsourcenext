@description('Name of the Application Insights instance')
param name string

@description('Location of the Application Insights instance')
param location string

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

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: empty(workspaceResourceId) ? null : workspaceResourceId
  }
  tags: tags
}

output id string = appInsights.id
output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
