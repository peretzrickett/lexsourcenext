// modules/sqlServer.bicep

@description('Name of the SQL Server')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Tags for the SQL Server')
param tags object = {}

@description('Administrator login for the SQL Server')
param adminLogin string

@description('Administrator password for the SQL Server')
@secure()
param adminPassword string

resource sqlServer 'Microsoft.Sql/servers@2021-05-01-preview' = {
  name: 'sql-${discriminator}-${clientName}'
  location: resourceGroup().location
  properties: {
    publicNetworkAccess: 'Disabled'
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
  }
}

// Private Endpoint for SQL Server
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${sqlServer.name}'
  params: {
    clientName: clientName
    discriminator: discriminator
    name: 'pe-${sqlServer.name}'
    privateLinkServiceId: sqlServer.id
    groupId: 'sqlServer'
    tags: tags
  }
}

output id string = sqlServer.id
