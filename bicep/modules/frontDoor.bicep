@description('Name of the Azure Front Door instance')
param name string

@description('SKU tier for the Azure Front Door')
@allowed([
  'Standard_AzureFrontDoor'
  'Premium_AzureFrontDoor'
])
param skuTier string = 'Premium_AzureFrontDoor'

@description('Frontend endpoints for the Azure Front Door')
param frontEndEndpoints array = []

@description('Backend pools for the Azure Front Door')
param backendPools array = []

@description('Routing rules for the Azure Front Door')
param routingRules array = []

// Placeholder to suppress warnings
var unusedParams = [
  frontEndEndpoints
  backendPools
  routingRules
]

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

@description('The resource ID of the Azure Front Door instance')
output id string = frontDoor.id

@description('The name of the Azure Front Door instance')
output name string = frontDoor.name
