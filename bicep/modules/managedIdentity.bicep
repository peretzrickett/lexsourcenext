@description('Name of the User Assigned Managed Identity')
param name string

@description('Azure region where the identity will be deployed')
param location string

// Define the User Assigned Managed Identity
// Note: We always try to create it, Azure will handle idempotency
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: location
}

// Define the Contributor role ID
@description('ID of the Contributor role') 
var roleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Output role information separately to avoid scope confusion
output roleDefinitionId string = roleId

@description('The resource ID of the UAMI')
output uamiId string = uami.id

@description('The principal ID of the UAMI')
output principalId string = uami.properties.principalId