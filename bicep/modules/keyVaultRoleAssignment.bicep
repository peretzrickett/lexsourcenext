@description('The Principal ID to assign the Key Vault Administrator role to')
param principalId string

@description('The Key Vault name')
param keyVaultName string

var kvRoleName = guid(resourceGroup().id, principalId, 'Key Vault Administrator')

// Get existing Key Vault
resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// Assign role to the Key Vault
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: kvRoleName
  scope: kv
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator
    principalType: 'ServicePrincipal'
  }
}

@description('Role Assignment resource ID')
output id string = roleAssignment.id