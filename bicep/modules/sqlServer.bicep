@description('Name of the SQL Server')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Location of the SQL Server')
param location string

@description('Subnet ID for Private Link')
param subnetId string

@description('Tags for the SQL Server')
param tags object = {}

@description('Administrator login for the SQL Server')
param adminLogin string

@description('Administrator password for the SQL Server')
@secure()
param adminPassword string

resource sqlServer 'Microsoft.Sql/servers@2021-05-01-preview' = {
  name: 'sql-${discriminator}-${clientName}'
  location: location
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
    location: location
    privateLinkServiceId: sqlServer.id
    privateDnsZoneName: 'privatelink${environment().suffixes.sqlServerHostname}'
    subnetId: subnetId
    groupId: 'sqlServer'
    tags: tags
  }
}

output id string = sqlServer.id
