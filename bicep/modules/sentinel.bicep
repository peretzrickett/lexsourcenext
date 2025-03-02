// modules/sentinel.bicep

@description('Geographic location for the Sentinel (Log Analytics) workspace')
param location string

@description('Name of the Sentinel (Log Analytics) workspace for monitoring')
param name string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Standard pricing tier for Log Analytics
    }
  }
}

@description('The resource ID of the deployed Log Analytics Workspace')
output id string = logAnalyticsWorkspace.id
