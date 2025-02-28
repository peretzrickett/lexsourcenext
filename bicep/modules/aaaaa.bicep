param clientNames array
param discriminator string
param endpointType string
param privateDnsZoneName string
param timeout int = 300

// Existing private endpoints
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: {
  name: 'pe-${endpointType}-${discriminator}-${name}'
  scope: resourceGroup('rg-${name}')
}]

resource privateStorageEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [for (name, index) in clientNames: {
  name: 'pe-stg${discriminator}${name}'
  scope: resourceGroup('rg-${name}')
}]

var allNames = union(clientNames, ['central'])

// Extract Private IP and FQDN
module privateIpExtractor 'vnetIpExtractor.bicep' = [for (name, index) in clientNames: {
  name: 'extractPrivateIp-${name}-${endpointType}'
  scope: resourceGroup('rg-central')
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

// Deploy the script to create DNS records for all resource groups, using privateIpExtractor outputs
resource createDnsRecords 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (name, index) in clientNames: {
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

      # Use IPs and FQDNs directly from privateIpExtractor
      IFS=$'\n' read -r -d '' -a ips <<< "$PRIVATE_IPS"
      IFS=$'\n' read -r -d '' -a fqdns <<< "$PRIVATE_FQDNS"

      echo "Creating Private DNS A Records in $RESOURCE_GROUP..."
      for fqdn in "${fqdns[@]}"; do
          for ip in "${ips[@]}"; do
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

      echo "{\"privateDnsRecords\": \"Created A records for ${#fqdns[@]} FQDNs and ${#ips[@]} IPs in $RESOURCE_GROUP\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      {
        name: 'PRIVATE_IPS'
        value: join(privateIpExtractor[index].outputs.privateIps, '\n')
      }
      {
        name: 'PRIVATE_FQDNS'
        value: join(privateIpExtractor[index].outputs.privateFqdns, '\n')
      }
      {
        name: 'privateDnsZoneName'
        value: privateDnsZoneName
      }
    ]
    timeout: 'PT${timeout}S'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    dependsOn: [privateIpExtractor[index]] // Ensure privateIpExtractor runs first
  }
}]
