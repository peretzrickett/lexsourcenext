// This module creates a role assignment at the subscription level
targetScope = 'subscription'

@description('Principal ID to assign the role to')
param principalId string

@description('Role definition ID to assign')
param roleDefinitionId string

@description('Optional principal type')
param principalType string = 'ServicePrincipal'

// Generate deterministic GUID for role assignment name
var roleAssignmentName = guid(subscription().id, principalId, roleDefinitionId)

// Create the role assignment, with the understanding it may fail if it already exists
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName 
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: principalType
  }
}

output roleAssignmentId string = roleAssignment.id