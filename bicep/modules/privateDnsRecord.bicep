// modules/privateDnsRecord.bicep

@description('List of client names for extracting private endpoint information')
param clientNames array

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Type of endpoint service for DNS record creation')
param endpointType string

@description('Name of the private DNS zone where records will be created')
param privateDnsZoneName string

@description('Timeout duration in seconds for the deployment script, defaults to 300 seconds')
param timeout int = 600

// Existing private endpoints for non-App Service resources (only in spoke VNets)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: if (endpointType != 'app') {
  name: 'pe-${endpointType}-${discriminator}-${name}'
  scope: resourceGroup('rg-${name}')
}]

resource privateStorageEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: if (endpointType == 'stg') {
  name: 'pe-stg${discriminator}${name}'
  scope: resourceGroup('rg-${name}')
}]

// Extract Private IPs and FQDNs for non-App Service resources in each spoke
module privateIpExtractor 'vnetIpExtractor.bicep' = [for (name, index) in clientNames: if (endpointType != 'app') {
  name: 'extractPrivateIp-${name}-${endpointType}'
  scope: resourceGroup('rg-${name}')
  params: {
    privateEndpointId: (endpointType == 'stg') ? privateStorageEndpoint[index].id : privateEndpoint[index].id
    timeout: timeout
    endpointType: endpointType
    clientName: name
    discriminator: discriminator
  }
  dependsOn: [
    privateEndpoint[index]
    privateStorageEndpoint[index]
  ]
}]

// Deploy the script to create DNS records in rg-central for all private endpoints
// Handle App Service (endpointType 'app') separately, as AFD manages it
resource createDnsRecords 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-dns-records-${endpointType}-${uniqueString(resourceGroup().id, deployment().name, subscription().subscriptionId, endpointType)}'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-Central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      #!/bin/bash
      set -e

      RESOURCE_GROUP="rg-central"
      DNS_ZONE_NAME="$privateDnsZoneName"
      SUBSCRIPTION_ID=$(az account show --query id -o tsv)

      echo "Subscription: $SUBSCRIPTION_ID"
      echo "Resource Group: $RESOURCE_GROUP"
      echo "DNS Zone: $DNS_ZONE_NAME"
      echo "Endpoint Type: $ENDPOINT_TYPE"
      echo "Clients: $clientNames"

      # Validate subscription context
      if [ -z "$SUBSCRIPTION_ID" ]; then
        echo "Error: Subscription ID is empty"
        exit 1
      fi
      az account set --subscription "$SUBSCRIPTION_ID" || {
        echo "Error: Failed to set subscription $SUBSCRIPTION_ID"
        exit 1
      }

      # Handle App Service (skipped as AFD-managed)
      if [ "$ENDPOINT_TYPE" = "app" ]; then
        echo "Skipping App Service DNS - managed by AFD"
        echo "{\"privateDnsRecords\": \"Skipped App Service DNS records, managed by AFD\"}" \
          > $AZ_SCRIPTS_OUTPUT_PATH
        exit 0
      fi

      # Collect IPs and FQDNs from spoke deployments
      ALL_IPS=""
      ALL_FQDNS=""
      for SPOKE in ${clientNames//,/ }; do
        echo "Checking rg-$SPOKE for $ENDPOINT_TYPE..."
        IPS=$(az deployment group show \
          -g "rg-$SPOKE" \
          -n "extractPrivateIp-$SPOKE-$ENDPOINT_TYPE" \
          --query "properties.outputs.privateIps.value" \
          -o tsv 2>/dev/null || echo "")
        FQDNS=$(az deployment group show \
          -g "rg-$SPOKE" \
          -n "extractPrivateIp-$SPOKE-$ENDPOINT_TYPE" \
          --query "properties.outputs.privateFqdns.value" \
          -o tsv 2>/dev/null || echo "")
        ALL_IPS="$ALL_IPS,$IPS"
        ALL_FQDNS="$ALL_FQDNS,$FQDNS"
      done

      # Clean and validate collected data
      IPS=$(echo "$ALL_IPS" | tr ',' '\n' | sort -u | grep -v "^$" | tr '\n' ' ')
      FQDNS=$(echo "$ALL_FQDNS" | tr ',' '\n' | sort -u | grep -v "^$" | tr '\n' ' ')
      echo "Collected IPs: $IPS"
      echo "Collected FQDNs: $FQDNS"

      if [ -z "$IPS" ] || [ -z "$FQDNS" ]; then
        echo "Error: No valid IPs or FQDNs for $ENDPOINT_TYPE"
        echo "{\"privateDnsRecords\": \"Failed: No valid IPs or FQDNs for $ENDPOINT_TYPE\"}" \
          > $AZ_SCRIPTS_OUTPUT_PATH
        exit 1
      fi

      # Create DNS A records
      for fqdn in $FQDNS; do
        for ip in $IPS; do
          echo "Checking A record for $fqdn -> $ip..."
          if ! az network private-dns record-set a show \
            -g "$RESOURCE_GROUP" \
            -z "$DNS_ZONE_NAME" \
            -n "$fqdn" \
            --query "aRecords[?ipv4Address=='$ip']" \
            -o tsv 2>/dev/null; then
            echo "Creating A record for $fqdn -> $ip"
            az network private-dns record-set a create \
              -g "$RESOURCE_GROUP" \
              -z "$DNS_ZONE_NAME" \
              -n "$fqdn" \
              --ttl 3600 || {
              echo "Error: Failed to create A record for $fqdn"
              exit 1
            }
            az network private-dns record-set a add-record \
              -g "$RESOURCE_GROUP" \
              -z "$DNS_ZONE_NAME" \
              -n "$fqdn" \
              --ipv4-address "$ip" || {
              echo "Error: Failed to add IP $ip to $fqdn"
              exit 1
            }
          else
            echo "A record for $fqdn -> $ip exists, skipping"
          fi
        done
      done

      echo "Created DNS records for $ENDPOINT_TYPE"
      echo "{\"privateDnsRecords\": \"Created A records for $ENDPOINT_TYPE\"}" \
        > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      {
        name: 'clientNames'
        value: join(clientNames, ',')
      }
      {
        name: 'ENDPOINT_TYPE'
        value: endpointType
      }
      {
        name: 'privateDnsZoneName'
        value: privateDnsZoneName
      }
    ]
    timeout: 'PT${timeout}S'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
  }
  dependsOn: [privateIpExtractor]
}
