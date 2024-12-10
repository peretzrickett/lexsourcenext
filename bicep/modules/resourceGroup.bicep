targetScope = 'subscription'

@description('Name of the Resource Group')
param name string

@description('Location where the Resource Group will be created')
param location string

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = if (subscription().id != '') {
  name: name
  location: location
}

@description('The resource ID of the Resource Group')
output id string = resourceGroup.id
