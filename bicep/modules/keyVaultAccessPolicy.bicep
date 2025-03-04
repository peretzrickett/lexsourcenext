// modules/keyVaultAccessPolicy.bicep
// Module for managing Key Vault access policies

@description('Name of the Key Vault to configure access policy for')
param keyVaultName string

@description('Object ID (principal ID) to grant permissions to')
param objectId string

@description('Permissions to grant on keys')
param permissions object = {
  keys: []
  secrets: []
  certificates: []
  storage: []
}

@description('Application ID of the service principal')
param applicationId string = ''

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// Add access policy to Key Vault
resource accessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: objectId
        applicationId: !empty(applicationId) ? applicationId : null
        permissions: permissions
      }
    ]
  }
}

@description('Access policy resource ID')
output accessPolicyId string = accessPolicy.id