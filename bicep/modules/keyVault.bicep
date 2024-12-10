@description('Name of the Key Vault')
param name string

@description('Location of the Key Vault')
param location string

@description('SKU of the Key Vault (standard or premium)')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Object ID of the administrator or application requiring access')
param accessPolicies array = []

@description('Soft delete retention period in days (minimum 7 days)')
param softDeleteRetentionDays int = 90

@description('Enable purge protection for the Key Vault')
param enablePurgeProtection bool = true

@description('Tags to apply to the Key Vault')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: name
  location: location
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    accessPolicies: accessPolicies
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionDays
    enablePurgeProtection: enablePurgeProtection
  }
  tags: tags
}

output id string = keyVault.id
output vaultUri string = keyVault.properties.vaultUri
output name string = keyVault.name
