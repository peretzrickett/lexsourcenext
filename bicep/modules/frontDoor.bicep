param location string

resource frontDoor 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: 'globalFrontDoor'
  location: location
  properties: {
    sku: {
      name: 'Standard_AzureFrontDoor'
    }
  }
}

output id string = frontDoor.id
