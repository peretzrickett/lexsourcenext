// modules/appInsights.bicep

@description('Name of the client for the Application Insights instance')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Type of application for Application Insights monitoring')
@allowed([
  'web'
  'other'
  'java'
  'node.js'
])
param applicationType string = 'web'

@description('Tags for organizing and billing the Application Insights instance')
param tags object = {}

@description('Flag to enable Private Link Scope integration for enhanced security')
param enablePrivateLinkScope bool = true

@description('Flag to restrict public access to Application Insights for security')
param restrictPublicAccess bool = true

@description('Flag to enable Private Link for the Application Insights instance')
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

// Log Analytics Workspace for Application Insights data
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

// Scoped Resource linking Application Insights to Private Link Scope
resource scopedResource 'microsoft.insights/privateLinkScopes/scopedResources@2021-07-01-preview' = if (enablePrivateLink) {
  name: privateLinkScope.name
  parent: privateLinkScope
  properties: {
    linkedResourceId: appInsights.id
  }
}

// Private Endpoint for App Insights (manual, linked to privatelink.monitor.azure.com)
module privateEndpoint 'privateEndpoint.bicep' = if (enablePrivateLink) {
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

@description('The resource ID of the Application Insights instance')
output id string = appInsights.id

@description('The instrumentation key for Application Insights monitoring')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string for Application Insights connectivity')
output connectionString string = appInsights.properties.ConnectionString

@description('The resource ID of the Application Insights instance for reference')
output appInsightsId string = appInsights.id

@description('The resource ID of the Private Link Scope, if enabled')
output privateLinkScopeId string = enablePrivateLinkScope ? privateLinkScope.id : ''

@description('The resource ID of the associated Log Analytics Workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource ID of the Private Endpoint for App Insights, if enabled')
output privateEndpointId string = enablePrivateLink ? privateEndpoint.outputs.id : ''
