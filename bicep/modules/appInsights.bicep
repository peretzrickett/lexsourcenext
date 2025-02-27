// modules/appInsights.bicep

@description('Name of the client')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Application type for Application Insights')
@allowed([
  'web'
  'other'
  'java'
  'node.js'
])
param applicationType string = 'web'

@description('Tags for the Application Insights instance')
param tags object = {}

@description('Enable Private Link Scope integration')
param enablePrivateLinkScope bool = true

@description('Restrict public access to Application Insights')
param restrictPublicAccess bool = true

@description('Enable Private Link Scope for the Application Insights instance')
param enablePrivateLink bool

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'pai-${discriminator}-${clientName}'
  location: resourceGroup().location
  kind: applicationType
  tags: tags
  properties: {
    Application_Type: applicationType
    publicNetworkAccessForIngestion: restrictPublicAccess ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: restrictPublicAccess ? 'Disabled' : 'Enabled'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics' 
  }
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${discriminator}-${clientName}'
  location: resourceGroup().location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource privateLinkScope 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = if (enablePrivateLinkScope) {
  name: 'pls-${discriminator}-${clientName}'
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

// Scoped Resource for Application Insights
resource scopedResource 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = if (enablePrivateLink) {
  name: privateLinkScope.name
  parent: privateLinkScope
  properties: {
    linkedResourceId: appInsights.id
  }
}

// Private Endpoint for App Insights
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${appInsights.name}'
  params: {
    clientName: clientName
    discriminator: discriminator
    name: 'pe-${appInsights.name}'
    privateLinkServiceId: privateLinkScope.id
    groupId: 'azuremonitor'
    tags: tags
  }
}
@description('The resource ID of the App Insights')
output id string = appInsights.id

@description('The instrumentation key of the App Insights')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string of the App Insights')
output connectionString string = appInsights.properties.ConnectionString

@description('The App Insights resource Id')
output appInsightsId string = appInsights.id

@description('The Private Link Scope resource Id')
output privateLinkScopeId string = enablePrivateLinkScope ? privateLinkScope.id : ''

@description('The Private Link Scope Association resource Id')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
