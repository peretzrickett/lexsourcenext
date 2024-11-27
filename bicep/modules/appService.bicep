param name string
param location string
param appServicePlanId string

resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: name
  location: location
  properties: {
    serverFarmId: appServicePlanId
  }
}

output id string = appService.id
