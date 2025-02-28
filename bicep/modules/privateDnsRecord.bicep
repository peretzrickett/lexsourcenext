param clientNames array = ['clienta', 'clientb'] // Spoke clients only
param discriminator string
param endpointType string
param privateDnsZoneName string
param timeout int = 3600

// Existing private endpoints (only in spoke VNets)
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: {
  name: 'pe-${endpointType}-${discriminator}-${name}'
  scope: resourceGroup('rg-${name}')
}]

resource privateStorageEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: {
  name: 'pe-stg${discriminator}${name}'
  scope: resourceGroup('rg-${name}')
}]

// Extract Private IPs and FQDNs for each spoke
module privateIpExtractor 'vnetIpExtractor.bicep' = [for (name, index) in clientNames: {
  name: 'extractPrivateIp-${name}-${endpointType}'
  scope: resourceGroup('rg-${name}') // Extract in spoke RGs
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

// Deploy the script to create DNS records for each resource group, handling union in script
resource createDnsRecords 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (name, index) in union(clientNames, ['Central']): {
  name: 'create-dns-records-${name}-${endpointType}-${uniqueString(resourceGroup().id, deployment().name, subscription().subscriptionId, name)}'
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
      RESOURCE_GROUP="rg-${name}"
      DNS_ZONE_NAME="${privateDnsZoneName}"

      # Collect all PRIVATE_IPS and PRIVATE_FQDNS from spokes for rg-central
      if [ "$RESOURCE_GROUP" = "rg-Central" ]; then
        ALL_IPS=""
        ALL_FQDNS=""
        for SPOKE in ${clientNames//,/ }; do
          SPOKE_IPS=$(az deployment group show --resource-group "rg-$SPOKE" --name "extractPrivateIp-$SPOKE-$ENDPOINT_TYPE" --query "properties.outputs.privateIps.value" -o tsv 2>/dev/null || echo "")
          SPOKE_FQDNS=$(az deployment group show --resource-group "rg-$SPOKE" --name "extractPrivateIp-$SPOKE-$ENDPOINT_TYPE" --query "properties.outputs.privateFqdns.value" -o tsv 2>/dev/null || echo "")
          ALL_IPS="$ALL_IPS\n$SPOKE_IPS"
          ALL_FQDNS="$ALL_FQDNS\n$SPOKE_FQDNS"
        done
        # Remove first empty line, deduplicate, and handle empty results
        IPS=$(echo -e "$ALL_IPS" | tail -n +2 | sort -u | grep -v "^$" || echo "")
        FQDNS=$(echo -e "$ALL_FQDNS" | tail -n +2 | sort -u | grep -v "^$" || echo "")
        if [ -z "$IPS" ] || [ -z "$FQDNS" ]; then
          echo "Error: No IPs or FQDNs collected from spokes"
          exit 1
        fi
      else
        # Use individual IPs and FQDNs for spokes
        IFS=$'\n' read -r -d '' -a IPS <<< "$PRIVATE_IPS" || IPS=()
        IFS=$'\n' read -r -d '' -a FQDNS <<< "$PRIVATE_FQDNS" || FQDNS=()
      fi

      echo "Creating Private DNS A Records in $RESOURCE_GROUP..."
      for fqdn in "${FQDNS[@]}"; do
          for ip in "${IPS[@]}"; do
              echo "Checking if A record exists for $fqdn..."
              existing_record=$(az network private-dns record-set a show \
                --resource-group "$RESOURCE_GROUP" \
                --zone-name "$DNS_ZONE_NAME" \
                --name "$fqdn" \
                --query "aRecords[?ipv4Address=='$ip']" \
                --output tsv || echo "not found")

              if [[ "$existing_record" == "not found" ]]; then
                  echo "Creating A record for $fqdn -> $ip"
                  az network private-dns record-set a create --resource-group "$RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" --name "$fqdn" --ttl 3600 || {
                      echo "Error: Failed to create A record for $fqdn"
                      exit 1
                  }
                  az network private-dns record-set a add-record --resource-group "$RESOURCE_GROUP" --zone-name "$DNS_ZONE_NAME" --record-set-name "$fqdn" --ipv4-address "$ip" || {
                      echo "Error: Failed to add IP $ip to A record for $fqdn"
                      exit 1
                  }
              else
                  echo "A record for $fqdn -> $ip already exists. Skipping creation."
              fi
          done
      done

      echo "{\"privateDnsRecords\": \"Created A records for ${#FQDNS[@]} FQDNs and ${#IPS[@]} IPs in $RESOURCE_GROUP\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      {
        name: 'PRIVATE_IPS'
        value: index < length(clientNames) ? join(privateIpExtractor[index].outputs.privateIps, '\n') : ''
      }
      {
        name: 'PRIVATE_FQDNS'
        value: index < length(clientNames) ? join(privateIpExtractor[index].outputs.privateFqdns, '\n') : ''
      }
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
  dependsOn: [privateIpExtractor] // Ensure all extractors run first
}]
