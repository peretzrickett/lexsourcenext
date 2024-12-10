param location string
param name string

resource frontDoor 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
}

output id string = frontDoor.id
