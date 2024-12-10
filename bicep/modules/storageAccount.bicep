@description('Name of the storage account')
param name string

@description('Location of the storage account')
param location string

@description('Replication type for the storage account')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param skuName string = 'Standard_LRS'

@description('Access tier for the storage account (only applicable to Standard accounts)')
@allowed([
  'Hot'
  'Cool'
])
param accessTier string = 'Hot'

@description('Indicates whether the storage account is a general-purpose V2 account')
param kind string = 'StorageV2'

@description('Tags to apply to the storage account')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: name
  location: location
  sku: {
    name: skuName
  }
  kind: kind
  properties: {
    accessTier: accessTier
  }
  tags: tags
}

output id string = storageAccount.id
