// modules/privateDnsRecord.bicep

param clientNames array
param discriminator string
param endpointType string
param privateDnsZoneName string
param timeout int = 300

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [ for (name, index) in clientNames: {
  name: 'pe-${endpointType}-${discriminator}-${name}'
  scope: resourceGroup('rg-${name}')
}]

resource privateStorageEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' existing = [ for (name, index) in clientNames: {
  name: 'pe-stg${discriminator}${name}'
  scope: resourceGroup('rg-${name}')
}]

// Extract Private IP and FQDN
module privateIpExtractor 'vnetIpExtractor.bicep' = [ for (name, index) in clientNames: {
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

// Deploy the script that creates the DNS records
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
      RESOURCE_GROUP="${RESOURCE_GROUP}"
      DNS_ZONE_NAME="${privateDnsZoneName}"

      echo "Checking for Private IPs..."
      RETRIES=10
      SLEEP_INTERVAL=30
      while [[ -z "$PRIVATE_IPS" && $RETRIES -gt 0 ]]; do
        echo "Waiting for Private Endpoint IP assignment... Retries left: $RETRIES"
        sleep $SLEEP_INTERVAL
        PRIVATE_IPS="$(az network private-endpoint show \
          --name "${name}" \
          --resource-group "${RESOURCE_GROUP}" \
          --query 'customDnsConfigs[*].ipAddresses' --output tsv)"
        ((RETRIES--))
      done

      if [[ -z "$PRIVATE_IPS" ]]; then
        echo "Error: Private Endpoint did not receive an IP address in time."
        exit 1
      fi

      # Convert IPs into an array
      IFS=$'\n' read -r -d '' -a ips <<< "$PRIVATE_IPS"
      IFS=$'\n' read -r -d '' -a fqdns <<< "$PRIVATE_FQDNS"

      echo "Creating Private DNS A Records..."
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

      echo "{\"privateDnsRecords\": \"Created A records for ${#fqdns[@]} FQDNs and ${#ips[@]} IPs\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      {
        name: 'RESOURCE_GROUP'
        value: resourceGroup().name
      }
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
    timeout: 'PT${timeout}S' // Keeping the timeout
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
  }
}]
