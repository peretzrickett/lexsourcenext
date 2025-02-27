// modules/vnetIpExtractor.bicep

@description('ID of the Private Endpoint')
param privateEndpointId string

@description('Timeout for the script execution in seconds')
param timeout int = 300

@description('Type of service for additional DNS configuration (e.g., "AppService", "AppInsights", "LogAnalytics", "KeyVault", "SqlServer", "Storage")')
@allowed([
  'app'
  'pai'
  'law'
  'pkv'
  'sql'
  'stg'
])
param endpointType string = 'app'

@description('Client name for the Private Endpoint')
param clientName string

@description('Discriminator for the Private Endpoint')
param discriminator string

// Reference the existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'uami-deployment-scripts'
  scope: resourceGroup('rg-central') // Ensure this matches the UAMI's resource group
}

var endpointName = (endpointType == 'stg') ? toLower('ep-${endpointType}${discriminator}${clientName}') : 'ep-${endpointType}-${discriminator}-${clientName}'

// Deploy the script that retrieves the Private IPs and generates FQDNs
resource privateIpRetrieval 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'extract-private-ip-${endpointName}-${uniqueString(resourceGroup().id, deployment().name, subscription().subscriptionId, endpointName)}'
  kind: 'AzureCLI'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      # Echo variables for debugging
      echo "Subscription ID: $SUBSCRIPTION_ID"
      echo "Private Endpoint ID: $PRIVATE_ENDPOINT_ID"
      echo "Service Type: $ENDPOINT_TYPE"
      echo "Client Name: $CLIENT_NAME"
      echo "Discriminator: $DISCRIMINATOR"
      echo "Region: $REGION"
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

      # Retrieve all Private IPs from Private Endpoint
      PRIVATE_IPS=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[*].ipConfigurations[*].privateIPAddress" -o tsv 2>/dev/null | sort -u)

      # Enhanced error handling
      if [ -z "$PRIVATE_IPS" ]; then
          echo "Error: No private IPs found for Private Endpoint $PRIVATE_ENDPOINT_ID"
          echo "Checking NIC and IP configurations..."
          NIC_IDS=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[*].id" -o tsv 2>/dev/null)
          if [ -n "$NIC_IDS" ]; then
              echo "NIC IDs: $NIC_IDS"
              PRIVATE_IPS=""
              for NIC_ID in $NIC_IDS; do
                  NIC_IP=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[?contains(name, 'privateEndpointIpConfig')].privateIpAddress" -o tsv 2>/dev/null | head -n 1)
                  if [ -n "$NIC_IP" ]; then
                      echo "Found Private IP via NIC: $NIC_IP"
                      PRIVATE_IPS="$PRIVATE_IPS\n$NIC_IP"
                  else
                      echo "No private endpoint IP configuration found in NIC $NIC_ID"
                      az network nic show --ids "$NIC_ID" --query "ipConfigurations" -o json
                  fi
              done
              PRIVATE_IPS=$(echo -e "$PRIVATE_IPS" | tail -n +2 | sort -u) # Remove first empty line and unique IPs
              if [ -z "$PRIVATE_IPS" ]; then
                  echo "No valid private IPs found after NIC check"
                  exit 1
              fi
          else
              echo "No NICs found for Private Endpoint"
              exit 1
          fi
      fi

      # Validate each private IP format
      VALID_IPS=""
      for IP in $PRIVATE_IPS; do
          if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
              echo "Valid Private IP: $IP"
              VALID_IPS="$VALID_IPS\n$IP"
          else
              echo "Error: Invalid private IP format: $IP"
          fi
      done
      PRIVATE_IPS=$(echo -e "$VALID_IPS" | tail -n +2) # Remove first empty line

      if [ -z "$PRIVATE_IPS" ]; then
          echo "Error: No valid private IPs after validation"
          exit 1
      fi

      # Dynamically generate FQDNs based on service type and region
      PRIVATE_FQDNS=""
      case "$ENDPOINT_TYPE" in
        "app")
          PRIVATE_FQDNS="app-${DISCRIMINATOR}-${CLIENT_NAME}.azurewebsites.net\napp-${DISCRIMINATOR}-${CLIENT_NAME}.scm.azurewebsites.net\napp-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.azurewebsites.net\napp-${DISCRIMINATOR}-${CLIENT_NAME}.scm.privatelink.azurewebsites.net"
          ;;
        "pai")
          PRIVATE_FQDNS="pai-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.monitor.azure.com"
          ;;
        "law")
          PRIVATE_FQDNS="law-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.monitor.azure.com"
          ;;
        "pkv")
          PRIVATE_FQDNS="pkv-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.vaultcore.azure.net"
          ;;
        "sql")
          PRIVATE_FQDNS="sql-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.database.windows.net"  # Simplified to a single valid FQDN
          ;;
        "stg")
          PRIVATE_FQDNS="stg${DISCRIMINATOR}${CLIENT_NAME}.privatelink.blob.${STORAGE_SUFFIX}\n${CLIENT_NAME}.privatelink.queue.${STORAGE_SUFFIX}\n${CLIENT_NAME}.privatelink.table.${STORAGE_SUFFIX}\n${CLIENT_NAME}.privatelink.file.${STORAGE_SUFFIX}"
          ;;
        *)
          echo "Error: Unsupported service type: $ENDPOINT_TYPE"
          exit 1
          ;;
      esac

      if [ -z "$PRIVATE_FQDNS" ]; then
          echo "Error: No FQDNs determined for service type $ENDPOINT_TYPE"
          exit 1
      fi

      # Output Private IPs and FQDNs as a JSON object to scriptoutputs.json
      echo "{\"privateIps\": [\"$PRIVATE_IPS\"], \"privateFqdns\": [\"$PRIVATE_FQDNS\"]}" > $AZ_SCRIPTS_OUTPUT_PATH
      echo "Private IPs: $PRIVATE_IPS" # Log to console for debugging
      echo "Private FQDNs: $PRIVATE_FQDNS" # Log to console for debugging
      echo "::set-output name=privateIps::$PRIVATE_IPS" # GitHub Actions-style output for IPs
      echo "::set-output name=privateFqdns::$PRIVATE_FQDNS" # GitHub Actions-style output for FQDNs
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
      {
        name: 'ENDPOINT_TYPE'
        value: endpointType
      }
      {
        name: 'CLIENT_NAME'
        value: clientName
      }
      {
        name: 'DISCRIMINATOR'
        value: discriminator
      }
      {
        name: 'REGION'
        value: resourceGroup().location
      }
      {
        name: 'STORAGE_SUFFIX'
        value: environment().suffixes.storage
      }
    ]
    timeout: 'PT${timeout}S' // Use the timeout parameter
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
  }
  dependsOn: [uami] // Ensure UAMI is referenced
}

// Output the retrieved Private IP Addresses and FQDNs
output privateIps array = privateIpRetrieval.properties.outputs.privateIps
output privateFqdns array = privateIpRetrieval.properties.outputs.privateFqdns
