@description('The name of the role assignment (deterministic GUID)')
param roleAssignmentName string

@description('The role definition ID to assign')
param roleDefinitionId string

@description('The principal ID to assign the role to')
param principalId string

// Create role assignment at subscription level
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
  }
}

@description('Role assignment ID')
output roleAssignmentId string = roleAssignment.id