// modules/keyVault.bicep

@description('Name of the client for the Key Vault instance')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('SKU of the Key Vault, defaults to standard')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Access policies defining permissions for administrators or applications')
param accessPolicies array = []

@description('Soft delete retention period in days, minimum 7 days for recovery')
param softDeleteRetentionDays int = 7

@description('Flag to enable purge protection for enhanced security')
param enablePurgeProtection bool = true

@description('Tags for organizing and billing the Key Vault instance')
param tags object = {}

// Create the Key Vault resource
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'pkv-${discriminator}-${clientName}'
  location: resourceGroup().location
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

// Private Endpoint for Key Vault (manual, not managed by AFD)
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${keyVault.name}'
  params: {
    clientName: clientName
    discriminator: discriminator
    name: 'pe-${keyVault.name}'
    privateLinkServiceId: keyVault.id
    groupId: 'vault'
    tags: tags
  }
}

@description('The resource ID of the deployed Key Vault instance')
output id string = keyVault.id

@description('The URI of the Key Vault for accessing secrets, keys, and certificates')
output vaultUri string = keyVault.properties.vaultUri

@description('The name of the Key Vault instance for reference')
output name string = keyVault.name
