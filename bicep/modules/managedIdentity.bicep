@description('Name of the User Assigned Managed Identity')
param name string

@description('Azure region where the identity will be deployed')
param location string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string = ''

// Generate the final name with discriminator if provided
var identityName = !empty(discriminator) ? 'uami-${discriminator}-deploy' : name

// Define the User Assigned Managed Identity
// Note: We always try to create it, Azure will handle idempotency
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: {
    purpose: 'Deployment automation'
    description: 'Identity used for Azure deployment scripts and automation'
  }
}

// Define the Contributor role ID for reference
@description('ID of the Contributor role') 
var roleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

// Output role information separately to avoid scope confusion
output roleDefinitionId string = roleId

@description('The resource ID of the UAMI')
output uamiId string = uami.id

@description('The principal ID of the UAMI')
output principalId string = uami.properties.principalId

@description('The name of the created UAMI')
output uamiName string = uami.name
