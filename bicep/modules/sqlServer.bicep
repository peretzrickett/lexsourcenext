param name string
param location string
param adminLogin string
@secure()
param adminPassword string

resource sqlServer 'Microsoft.Sql/servers@2021-05-01-preview' = {
  name: name
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
  }
}

output id string = sqlServer.id
