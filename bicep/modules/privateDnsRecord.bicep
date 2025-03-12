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

@description('Location for resources')
param location string = resourceGroup().location

// Existing private endpoints for non-App Service resources (only in spoke VNets)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: if (endpointType != 'app') {
  name: 'pe-${endpointType}-${discriminator}-${name}'
  scope: resourceGroup('rg-${discriminator}-${name}')
}]

resource privateStorageEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: if (endpointType == 'stg') {
  name: 'pe-stg${discriminator}${name}'
  scope: resourceGroup('rg-${discriminator}-${name}')
}]

// Extract Private IPs and FQDNs for non-App Service resources in each spoke
// Note: Adding a unique suffix to avoid conflicts with previous deployments
module privateIpExtractor 'vnetIpExtractor.bicep' = [for (name, index) in clientNames: if (endpointType != 'app') {
  name: 'extractIp-${name}-${endpointType}-${uniqueString(resourceGroup().id, deployment().name)}'
  scope: resourceGroup('rg-${discriminator}-${name}')
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

// Deploy the script to create DNS records in resource group for all private endpoints
resource createDnsRecords 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-dns-records-${endpointType}-${uniqueString(resourceGroup().id, deployment().name, subscription().subscriptionId, endpointType)}'
  location: location
  kind: 'AzureCLI'
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

      RESOURCE_GROUP="$RESOURCE_GROUP"
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
        echo "Checking rg-$DISCRIMINATOR-$SPOKE for $ENDPOINT_TYPE..."
        # Search for any deployment that starts with extractIp and contains the endpoint type
        EXTRACT_IP_DEPLOYMENT=$(az deployment group list \
          -g "rg-$DISCRIMINATOR-$SPOKE" \
          --query "[?starts_with(name, 'extractIp-${SPOKE}-${ENDPOINT_TYPE}')].name" \
          -o tsv 2>/dev/null | head -1)
        
        if [ -z "$EXTRACT_IP_DEPLOYMENT" ]; then
          echo "No extractor deployment found for $SPOKE-$ENDPOINT_TYPE"
          continue
        fi
          
        echo "Found deployment: $EXTRACT_IP_DEPLOYMENT"
        IPS=$(az deployment group show \
          -g "rg-$DISCRIMINATOR-$SPOKE" \
          -n "$EXTRACT_IP_DEPLOYMENT" \
          --query "properties.outputs.privateIps.value" \
          -o tsv 2>/dev/null || echo "")
        FQDNS=$(az deployment group show \
          -g "rg-$DISCRIMINATOR-$SPOKE" \
          -n "$EXTRACT_IP_DEPLOYMENT" \
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
        # Remove trailing dots from FQDN if present
        fqdn=${fqdn%.}
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
      {
        name: 'DISCRIMINATOR'
        value: discriminator
      }
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
    ]
    timeout: 'PT${timeout}S'
    retentionInterval: 'PT6H'
    cleanupPreference: 'Always' // Always clean up, regardless of success or failure
  }
  dependsOn: [privateIpExtractor]
}
