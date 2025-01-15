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
  name: name
  location: location
  kind: applicationType
  tags: tags
  properties: {
    Application_Type: applicationType
    publicNetworkAccessForIngestion: restrictPublicAccess ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: restrictPublicAccess ? 'Disabled' : 'Enabled'
    IngestionMode: 'ApplicationInsights'
  }
}

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-09-01' = if (enablePrivateLinkScope) {
  name: 'pls-${name}'
  location: 'global'
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource privateLinkScopeAssociation 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = if (enablePrivateLink) {
  name: '${appInsightsName}-association'
  parent: privateLinkScope
  properties: {
    linkedResourceId: appInsights.id
  }
}

// Link Application Insights to Private Link Scope
resource scopedResources 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-09-01' = if (enablePrivateLink) {
  name: 'azuremonitor'
  parent: privateLinkScope
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

