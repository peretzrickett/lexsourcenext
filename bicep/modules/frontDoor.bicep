// modules/frontDoor.bicep

@description('Name of the Azure Front Door instance')
param name string

@description('SKU tier for the Azure Front Door')
@allowed([
  'Premium_AzureFrontDoor'
])
param skuTier string = 'Premium_AzureFrontDoor'

@description('Tags to apply to the Azure Front Door instance')
param tags object = {}

resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
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
