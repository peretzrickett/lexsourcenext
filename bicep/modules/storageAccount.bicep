// modules/storageAccount.bicep

@description('Name of the client for the Storage Account')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Replication type for the Storage Account, defaults to Standard_LRS')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

@description('Type of Storage Account, defaults to general-purpose V2')
param kind string = 'StorageV2'

@description('Flag to enable blob soft delete retention policy for data recovery')
param enableBlobSoftDelete bool = false

@description('Retention period in days for blob soft delete, defaults to disabled')
param blobSoftDeleteRetentionDays int = 0

@description('Flag to enable container soft delete retention policy for data recovery')
param enableContainerSoftDelete bool = false

@description('Retention period in days for container soft delete, defaults to disabled')
param containerSoftDeleteRetentionDays int = 0

@description('Tags for organizing and billing the Storage Account')
param tags object = {}

var storageAccountName = toLower('stg${discriminator}${clientName}')
var privateEndpointName = 'pe-${storageAccountName}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: resourceGroup().location
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    supportsHttpsTrafficOnly: true // Enforce HTTPS for security
  }
  tags: tags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-09-01' = {
  name: 'default'
  parent: storageAccount
  properties: {
    deleteRetentionPolicy: blobSoftDeleteRetentionDays > 0 ? {
      enabled: enableBlobSoftDelete
      days: blobSoftDeleteRetentionDays
    } : {
      enabled: false
    }
    containerDeleteRetentionPolicy: containerSoftDeleteRetentionDays > 0 ? {
      enabled: enableContainerSoftDelete
      days: containerSoftDeleteRetentionDays
    } : {
      enabled: false
    }
  }
}

// Private Endpoint for Storage Account (blob access, manual, not managed by AFD)
module privateEndpoint 'privateEndpoint.bicep' = {
  name: privateEndpointName
  params: {
    clientName: clientName
    discriminator: discriminator
    name: privateEndpointName
    privateLinkServiceId: storageAccount.id
    groupId: 'blob'
    tags: tags
  }
}

@description('The resource ID of the Storage Account')
output id string = storageAccount.id

@description('The name of the Storage Account for reference')
output name string = storageAccount.name

@description('The primary endpoints of the Storage Account for connectivity')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
