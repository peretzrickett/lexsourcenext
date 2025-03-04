@description('The principal ID to check role assignments for')
param principalId string

@description('The role definition ID to check')
param roleDefinitionId string

// Use a deployment script to check if the role assignment exists
resource checkRoleAssignment 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'check-role-assignment-exists-${uniqueString(principalId, roleDefinitionId)}'
  location: resourceGroup().location
  kind: 'AzureCLI'
  properties: {
    azCliVersion: '2.40.0'
    retentionInterval: 'P1D'
    scriptContent: '''
      #!/bin/bash
      
      PRINCIPAL_ID="$1"
      ROLE_ID="$2"
      
      # Check if role assignment exists at subscription level
      ROLE_ASSIGNMENT=$(az role assignment list --assignee "$PRINCIPAL_ID" --scope "/subscriptions/$(az account show --query id -o tsv)" 2>/dev/null | jq -r ".[] | select(.roleDefinitionId | endswith(\"$ROLE_ID\"))")
      
      if [ -n "$ROLE_ASSIGNMENT" ]; then
        echo "Role assignment exists"
        echo "{ \"exists\": true }" > $AZ_SCRIPTS_OUTPUT_PATH
      else
        echo "Role assignment does not exist"
        echo "{ \"exists\": false }" > $AZ_SCRIPTS_OUTPUT_PATH
      fi
    '''
    arguments: '${principalId} ${last(split(roleDefinitionId, '/'))}'
    timeout: 'PT5M'
    cleanupPreference: 'OnSuccess'
  }
}

@description('Whether the role assignment exists')
output exists bool = checkRoleAssignment.properties.outputs.exists