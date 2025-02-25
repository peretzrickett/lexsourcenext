@description('Name of the client')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Location of the Key Vault')
param location string

@description('Subnet ID for Private Link')
param subnetId string

@description('SKU of the Key Vault (standard or premium)')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Object ID of the administrator or application requiring access')
param accessPolicies array = []

@description('Soft delete retention period in days (minimum 7 days)')
param softDeleteRetentionDays int = 7

@description('Enable purge protection for the Key Vault')
param enablePurgeProtection bool = true

@description('Tags to apply to the Key Vault')
param tags object = {}

// Create the Key Vault resource
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'pkv-${discriminator}-${clientName}'
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

// Private Endpoint for Key Vault
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${keyVault.name}'
  params: {
    clientName: clientName
    discriminator: discriminator
    name: 'pe-${keyVault.name}'
    location: location
    privateLinkServiceId: keyVault.id
    privateDnsZoneName: 'privatelink.vaultcore.azure.net'
    groupId: 'vault'
    serviceType: 'KeyVault'
    tags: tags
  }
}

@description('The resource ID of the Key Vault')
output id string = keyVault.id

@description('The URI of the Key Vault')
output vaultUri string = keyVault.properties.vaultUri

@description('The name of the Key Vault')
output name string = keyVault.name


