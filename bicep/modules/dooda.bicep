@description('ID of the Private Endpoint')
param privateEndpointId string

@description('Name of the Private Endpoint')
param name string

@description('Timeout for the script execution in seconds')
param timeout int = 120

@description('Client name')
param clientName string

@description('Discriminator')
param discriminator string

// Reference the existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'uami-deployment-scripts'
  scope: resourceGroup('rg-central') // Ensure this matches the UAMI's resource group
}

// Deploy the script that retrieves the Private IP
resource privateIpRetrieval 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'extract-private-ip-${name}'
  kind: 'AzureCLI'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId(resourceGroup().name, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      # Echo variables for debugging
      echo "Subscription ID: $SUBSCRIPTION_ID"
      echo "Private Endpoint ID: $PRIVATE_ENDPOINT_ID"
      echo "Cloud: $(az cloud show --query name -o tsv)"

      # Check if subscription ID is empty
      if [ -z "$SUBSCRIPTION_ID" ]; then
          echo "Error: Subscription ID is empty or not set"
          exit 1
      fi

      # Ensure we're in AzureCloud
      current_cloud=$(az cloud show --query name -o tsv)
      if [ "$current_cloud" != "AzureCloud" ]; then
          echo "Switching to AzureCloud..."
          az cloud set --name AzureCloud || {
              echo "Error: Failed to switch to AzureCloud"
              exit 1
          }
      fi

      # Set the Azure CLI context to the specified subscription
      az account set --subscription "$SUBSCRIPTION_ID" || {
          echo "Error: Failed to set subscription context for $SUBSCRIPTION_ID"
          exit 1
      }

      # Verify the subscription is set correctly
      current_subscription=$(az account show --query id -o tsv)
      if [ "$current_subscription" != "$SUBSCRIPTION_ID" ]; then
          echo "Error: Current subscription ($current_subscription) does not match expected ($SUBSCRIPTION_ID)"
          exit 1
      fi

      # Retrieve Private Endpoint details for debugging
      echo "Private Endpoint Details:"
      az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces" -o json

      # Retrieve Private IP from Private Endpoint
      PRIVATE_IP=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[0].ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null)

      # Enhanced error handling
      if [ -z "$PRIVATE_IP" ]; then
          echo "Error: Private IP not found for Private Endpoint $PRIVATE_ENDPOINT_ID"
          echo "Checking NIC and IP configurations..."
          NIC_ID=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[0].id" -o tsv 2>/dev/null)
          if [ -n "$NIC_ID" ]; then
              echo "NIC ID: $NIC_ID"
              # Use a more specific query for the NIC's IP configuration
              NIC_IP=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[?contains(name, 'privateEndpointIpConfig')].privateIpAddress" -o tsv 2>/dev/null | head -n 1)
              if [ -n "$NIC_IP" ]; then
                  echo "Found Private IP via NIC: $NIC_IP"
                  PRIVATE_IP="$NIC_IP"
              else
                  echo "No private endpoint IP configuration found in NIC"
                  az network nic show --ids "$NIC_ID" --query "ipConfigurations" -o json
                  exit 1
              fi
          else
              echo "No NIC found for Private Endpoint"
              exit 1
          fi
      fi

      # Validate the private IP format
      if ! [[ "$PRIVATE_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          echo "Error: Invalid private IP format: $PRIVATE_IP"
          exit 1
      fi

      # Output Private IP as a JSON object to scriptoutputs.json
      echo "{\"privateIp\": \"$PRIVATE_IP\"}" > $AZ_SCRIPTS_OUTPUT_PATH
      echo "Private IP: $PRIVATE_IP" # Log to console for debugging
      echo "::set-output name=privateIp::$PRIVATE_IP" # GitHub Actions-style output for compatibility
    '''
    environmentVariables: [
      {
        name: 'SUBSCRIPTION_ID'
        value: subscription().subscriptionId // Use current subscription by default
      }
      {
        name: 'PRIVATE_ENDPOINT_ID'
        value: privateEndpointId
      }
    ]
    timeout: 'PT${timeout}S' // Use the timeout parameter
    retentionInterval: 'P1D'
  }
  dependsOn: [uami] // Ensure UAMI is referenced
}

// Output the retrieved Private IP Address
output privateIp string = privateIpRetrieval.properties.outputs.privateIp
