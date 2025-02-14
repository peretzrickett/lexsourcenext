@description('Name of the Storage Account')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Location where the Storage Account will be created')
param location string


@description('Subnet ID for Private Link connection')
param subnetId string

@description('Replication type for the Storage Account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

@description('Indicates whether the Storage Account is general-purpose V2')
param kind string = 'StorageV2'

@description('Enable blob soft delete retention policy')
param enableBlobSoftDelete bool = false

@description('Retention period in days for blob soft delete (set 0 to disable)')
param blobSoftDeleteRetentionDays int = 0

@description('Enable container soft delete retention policy')
param enableContainerSoftDelete bool = false

@description('Retention period in days for container soft delete (set 0 to disable)')
param containerSoftDeleteRetentionDays int = 0

@description('Tags to apply to the Storage Account')
param tags object = {}

var storageAccountName = 'stg${discriminator}${clientName}'
var privateEndpointName = 'pe-${storageAccountName}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    supportsHttpsTrafficOnly: true
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

// Private Endpoint for Storage Account (blob access)
module privateEndpoint 'privateEndpoint.bicep' = {
  name: privateEndpointName
  params: {
    clientName: clientName
    discriminator: discriminator
    name: privateEndpointName
    location: location
    privateLinkServiceId: storageAccount.id
    privateDnsZoneName: 'privatelink.${environment().suffixes.storage}'
    subnetId: subnetId
    groupId: 'blob'
    tags: tags
  }
}

@description('The resource ID of the Storage Account')
output id string = storageAccount.id

@description('The name of the Storage Account')
output name string = storageAccount.name

@description('The primary endpoints of the Storage Account')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints
