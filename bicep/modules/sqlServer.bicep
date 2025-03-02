// modules/sqlServer.bicep

@description('Name of the SQL Server instance for the client')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Tags for organizing and billing the SQL Server instance')
param tags object = {}

@description('Administrator login credential for the SQL Server')
param adminLogin string

@description('Administrator password credential for the SQL Server, marked as secure')
@secure()
param adminPassword string

resource sqlServer 'Microsoft.Sql/servers@2021-05-01-preview' = {
  name: 'sql-${discriminator}-${clientName}'
  location: resourceGroup().location
  properties: {
    publicNetworkAccess: 'Disabled' // Restrict public access for security
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
  }
}

// Private Endpoint for SQL Server (manual, linked to privatelink.database.windows.net)
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

@description('The resource ID of the SQL Server instance')
output id string = sqlServer.id

@description('The resource ID of the Private Endpoint for SQL Server')
output privateEndpointId string = privateEndpoint.outputs.id
