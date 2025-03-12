// modules/vnetIpExtractor.bicep

@description('Resource ID of the Private Endpoint to extract IP and FQDN information')
param privateEndpointId string

@description('Timeout duration in minutes for the script execution')
param timeout int = 20

@description('Type of service for additional DNS configuration, specifying the resource type')
@allowed([
  'app'
  'pai'
  'law'
  'pkv'
  'sql'
  'stg'
])
param endpointType string = 'app'

@description('Client name associated with the Private Endpoint or service')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

// Reference the existing User Assigned Managed Identity for script execution
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'uami-${discriminator}-deploy'
  scope: resourceGroup('rg-${discriminator}-central') // Ensure this matches the UAMI's resource group
}

var endpointName = (endpointType == 'stg') ? toLower('ep-${endpointType}${discriminator}${clientName}') : 'ep-${endpointType}-${discriminator}-${clientName}'

// Deploy the script to retrieve Private IPs and generate FQDNs for the Private Endpoint
// Skip for App Service (endpointType 'app') since AFD manages the private endpoint
resource privateIpRetrieval 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (endpointType != 'app') {
  name: 'extract-private-ip-${endpointName}-${uniqueString(resourceGroup().id, deployment().name, subscription().subscriptionId, endpointName)}'
  kind: 'AzureCLI'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-${discriminator}-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-${discriminator}-deploy')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "Subscription ID: $SUBSCRIPTION_ID"
      echo "Private Endpoint ID: $PRIVATE_ENDPOINT_ID"
      echo "Service Type: $ENDPOINT_TYPE"

      # Quick subscription check
      if [ -z "$SUBSCRIPTION_ID" ]; then
        echo "Error: Subscription ID is empty"
        exit 1
      fi
      az account set --subscription "$SUBSCRIPTION_ID" || {
        echo "Error: Failed to set subscription"
        exit 1
      }

      # Get Private IPs with timeout
      PRIVATE_IPS=$(timeout 120s az network private-endpoint show \
        --ids "$PRIVATE_ENDPOINT_ID" \
        --query "networkInterfaces[*].ipConfigurations[*].privateIPAddress" \
        -o tsv 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//')
      if [ -z "$PRIVATE_IPS" ]; then
        echo "No IPs found, checking NICs (limited to first NIC)..."
        NIC_ID=$(timeout 60s az network private-endpoint show \
          --ids "$PRIVATE_ENDPOINT_ID" \
          --query "networkInterfaces[0].id" \
          -o tsv 2>/dev/null)
        if [ -n "$NIC_ID" ]; then
          PRIVATE_IPS=$(timeout 60s az network nic show \
            --ids "$NIC_ID" \
            --query "ipConfigurations[?contains(name, 'privateEndpointIpConfig')].privateIpAddress" \
            -o tsv 2>/dev/null | head -n 1)
        fi
      fi

      # Validate IPs
      if [ -z "$PRIVATE_IPS" ]; then
        echo "Error: No valid private IPs found"
        exit 1
      fi
      VALID_IPS=""
      for IP in $(echo "$PRIVATE_IPS" | tr ',' '\n'); do
        if [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
          VALID_IPS="$VALID_IPS,$IP"
        fi
      done
      PRIVATE_IPS=$(echo "$VALID_IPS" | sed 's/^,//' | tr '\n' ',' | sed 's/,$//')
      if [ -z "$PRIVATE_IPS" ]; then
        echo "Error: No valid IPs after validation"
        exit 1
      fi

      # Get Azure environment specific domain suffixes
      SQL_DOMAIN=$(az cloud show --query 'suffixes.sqlServerHostname' -o tsv)
      # Remove leading dot if present
      SQL_DOMAIN=${SQL_DOMAIN#.}
      STORAGE_DOMAIN=$(az cloud show --query 'suffixes.storage' -o tsv)
      # Remove leading dot if present
      STORAGE_DOMAIN=${STORAGE_DOMAIN#.}
      KV_DOMAIN=$(az cloud show --query 'suffixes.keyVaultDns' -o tsv)
      # Remove leading dot if present
      KV_DOMAIN=${KV_DOMAIN#.}
      MONITOR_DOMAIN="privatelink.monitor.azure.com" # TODO: Get this from Azure CLI when available

      # Generate FQDNs
      case "$ENDPOINT_TYPE" in
        "pai") PRIVATE_FQDNS="pai-${DISCRIMINATOR}-${CLIENT_NAME}.${MONITOR_DOMAIN}" ;;
        "sql") PRIVATE_FQDNS="sql-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.${SQL_DOMAIN}" ;;
        "stg") PRIVATE_FQDNS="stg${DISCRIMINATOR}${CLIENT_NAME}.privatelink.blob.${STORAGE_DOMAIN}" ;;
        "pkv") PRIVATE_FQDNS="pkv-${DISCRIMINATOR}-${CLIENT_NAME}.privatelink.${KV_DOMAIN}" ;;
        "law") PRIVATE_FQDNS="law-${DISCRIMINATOR}-${CLIENT_NAME}.${MONITOR_DOMAIN}" ;;
        "app") echo "Skipping App Service"; \
              echo "{\"privateIps\": [], \"privateFqdns\": []}" > $AZ_SCRIPTS_OUTPUT_PATH; \
              exit 0 ;;
        *) echo "Error: Unsupported type $ENDPOINT_TYPE"; exit 1 ;;
      esac
      
      # Remove trailing dots from FQDNs if present
      PRIVATE_FQDNS=${PRIVATE_FQDNS%.}

      if [ -z "$PRIVATE_FQDNS" ]; then
        echo "Error: No FQDNs generated"
        exit 1
      fi

      # Output results
      echo "Private IPs: $PRIVATE_IPS"
      echo "Private FQDNs: $PRIVATE_FQDNS"
      echo "{\"privateIps\": [\"${PRIVATE_IPS//,/\",\"}\"], \"privateFqdns\": [\"${PRIVATE_FQDNS//,/\",\"}\"]}" \
        > $AZ_SCRIPTS_OUTPUT_PATH
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
        value: environment().suffixes.storage // Use environment function to get correct storage suffix
      }
    ]
    timeout: 'PT${timeout}M' // Using parameter value for timeout
    retentionInterval: 'PT6H' // Use 6 hours to maintain logs longer for debugging
    cleanupPreference: 'Always' // Always clean up, regardless of success or failure
  }
  dependsOn: [uami] // Ensure UAMI is referenced
}

// Output the retrieved Private IP Addresses and FQDNs, or empty for App Service
output privateIps array = endpointType != 'app' ? privateIpRetrieval.properties.outputs.privateIps : []
output privateFqdns array = endpointType != 'app' ? privateIpRetrieval.properties.outputs.privateFqdns : []
