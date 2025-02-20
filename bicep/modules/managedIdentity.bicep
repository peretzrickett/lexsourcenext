// @description('Name of the User Assigned Managed Identity')
// param name string

// // Define the User Assigned Managed Identity
// resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
//   name: name
// }

// // Generate a deterministic GUID for the role assignment name
// var roleAssignmentName = guid(subscription().id, uami.id, 'Contributor')

// // Define the Contributor role definition ID as a variable for clarity
// var contributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')

// // Conditionally define the role assignment (Bicep doesn’t natively check existence, but Azure handles idempotency)
// resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: roleAssignmentName
//   scope: subscription()
//   properties: {
//     roleDefinitionId: contributorRoleDefinitionId
//     principalId: uami.properties.principalId
//   }
// }

// @description('The resource ID of the UAMI')
// output uamiId string = uami.id
