@description('Name of the User Assigned Managed Identity')
param name string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: name
  location: resourceGroup().location
}

// Assign the Contributor role to the UAMI at the subscription level
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(uami.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role ID
    principalId: uami.properties.principalId
  }
}

@description('The resource ID of the UAMI')
output uamiId string = uami.id
