@description('Name of the Azure Front Door instance')
param name string

@description('Names of the clients to create Front Door resources for')
param clientNames array = []

@description('Distinguished qualifier for resources')
param discriminator string

@description('SKU tier for the Azure Front Door')
@allowed([
  'Premium_AzureFrontDoor'
])
param skuTier string = 'Premium_AzureFrontDoor'

@description('Tags to apply to the Azure Front Door instance')
param tags object = {}

resource frontDoor 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: name
  location: 'global'
  sku: {
    name: skuTier
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
  tags: tags
}

// Create Backend Pools for each client
resource afdBackendPools 'Microsoft.Cdn/profiles/afdOriginGroups@2021-06-01' = [for clientName in clientNames: {
  name: 'afd-backend-${discriminator}-${clientName}'
  parent: frontDoor
  properties: {
    sessionAffinityEnabledState: 'Disabled'
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
  }
}]

// Create Origins (App Services via Private DNS) for each client
resource afdOrigins 'Microsoft.Cdn/profiles/afdOriginGroups/origins@2021-06-01' = [for clientName in clientNames: {
  name: 'afd-origin-${discriminator}-${clientName}'
  parent: afdBackendPools[clientName]
  properties: {
    hostName: 'app-${clientName}.privatelink.azurewebsites.net'  // Private DNS name
    originHostHeader: 'app-${clientName}.privatelink.azurewebsites.net'
    httpPort: 80
    httpsPort: 443
    enabledState: 'Enabled'
  }
}]

// Create Frontend Endpoint
resource afdFrontend 'Microsoft.Cdn/profiles/afdEndpoints@2021-06-01' = [for clientName in clientNames: {
  name: 'afd-frontend-${discriminator}-${clientName}'
  location: 'global'
  parent: frontDoor
  properties: {
    enabledState: 'Enabled'
  }
}]

// Create Routing Rules for each client
resource afdRoutingRules 'Microsoft.Cdn/profiles/afdEndpoints/routes@2021-06-01' = [for clientName in clientNames: {
  name: 'afd-route-${discriminator}-${clientName}'
  parent: afdFrontend[clientName]
  properties: {
    supportedProtocols: [
      'Https'
    ]
    patternsToMatch: [
      '/${clientName}/*'
    ]
    originGroup: {
      id: afdBackendPools[clientName].id
    }
    forwardingProtocol: 'MatchRequest'
  }
}]

@description('The resource ID of the Azure Front Door instance')
output id string = frontDoor.id

@description('The name of the Azure Front Door instance')
output name string = frontDoor.name

