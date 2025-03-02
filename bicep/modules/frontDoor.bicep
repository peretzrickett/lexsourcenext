// modules/frontDoor.bicep

@description('Name of the Azure Front Door instance for global traffic management')
param name string

@description('SKU tier for the Azure Front Door, restricted to Premium for Private Link support')
@allowed([
  'Premium_AzureFrontDoor'
])
param skuTier string = 'Premium_AzureFrontDoor'

@description('Tags for organizing and billing the Azure Front Door instance')
param tags object = {}

resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: name
  location: 'global'
  sku: {
    name: skuTier
  }
  properties: {
    originResponseTimeoutSeconds: 60 // Configure timeout for origin responses
  }
  tags: tags
}

@description('The resource ID of the deployed Azure Front Door instance')
output id string = frontDoor.id

@description('The name of the Azure Front Door instance for reference')
output name string = frontDoor.name
