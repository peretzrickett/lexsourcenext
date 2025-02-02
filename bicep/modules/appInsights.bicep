@description('Name of the Log Analytics Workspace')
param logAnalyticsWorkspaceName string

@description('Location for the resources')
param location string

@description('Name of the Application Insights instance')
param name string

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

@description('Tags for the Application Insights instance')
param tags object = {}

@description('Enable Private Link Scope integration')
param enablePrivateLinkScope bool = true

@description('Restrict public access to Application Insights')
param restrictPublicAccess bool = true

@description('Name of the Application Insights instance')
param appInsightsName string

@description('Enable Private Link Scope for the Application Insights instance')
param enablePrivateLink bool

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'pai-{name}'
  location: location
  kind: applicationType
  tags: tags
  properties: {
    Application_Type: applicationType
    publicNetworkAccessForIngestion: restrictPublicAccess ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: restrictPublicAccess ? 'Disabled' : 'Enabled'
    IngestionMode: 'ApplicationInsights'
  }
  dependsOn: [
    logAnalyticsWorkspace
  ]
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${logAnalyticsWorkspaceName}'
  location: location
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource privateLinkScope 'microsoft.insights/privateLinkScopes@2021-07-01-preview' = if (enablePrivateLinkScope) {
  name: 'pls-${name}'
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource privateLinkScopeAssociation 'microsoft.insights/components/linkedStorageAccounts@2020-03-01-preview' = if (enablePrivateLink) {
  name: 'item'
  parent: appInsights
}

// Scoped Resource for Application Insights
resource scopedResource 'microsoft.insights/components/analyticsItems@2015-05-01' = if (enablePrivateLink) {
  name: 'item'
  parent: appInsights
  properties: {
    linkedResourceId: appInsights.id
  }
}

// Private Endpoint for App Insights
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${name}'
  params: {
    name: 'pe-${name}'
    location: location
    privateLinkServiceId: privateLinkScope.id
    subnetId: subnetId
    groupIds: [ 'azuremonitor' ]
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
