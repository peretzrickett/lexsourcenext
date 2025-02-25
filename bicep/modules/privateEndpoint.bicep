@description('Name of the Private Endpoint')
param name string

@description('Location where the Private Endpoint will be deployed')
param location string

@description('ID of the target resource for the Private Link connection')
param privateLinkServiceId string

@description('Client name for the Private Endpoint')
param clientName string

@description('Discriminator for the Private Endpoint')
param discriminator string

@description('Group ID(s) for the resource type (e.g., blob, sqlServer, vault, sites, insights)')
param groupId string

@description('Private DNS Zone Name (e.g., privatelink.azurewebsites.net, privatelink.monitor.azure.com)')
param privateDnsZoneName string = 'privatelink.azurewebsites.net'

@description('Tags to apply to the Private Endpoint')
param tags object = {}

@description('Timeout for the deployment script in seconds')
param timeout int = 120

@description('Type of service for additional DNS configuration (e.g., "AppService", "AppInsights", "LogAnalytics", "KeyVault", "SqlServer", "Storage")')
@allowed([
  'AppService'
  'AppInsights'
  'LogAnalytics'
  'KeyVault'
  'SqlServer'
  'Storage'
])
param serviceType string

@description('Region for the service, if applicable (e.g., "eastus")')
param region string = 'eastus'

// Reference an existing virtual network
resource existingVnet 'Microsoft.Network/virtualNetworks@2023-02-01' existing = {
  name: 'vnet-${discriminator}-${clientName}'
}

// Reference an existing subnet
resource existingSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-02-01' existing = {
  name: 'privateLink'
  parent: existingVnet
}

// Create the Private Endpoint
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: location
  properties: {
    subnet: {
      id: existingSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${name}'
        properties: {
          privateLinkServiceId: privateLinkServiceId
          groupIds: [groupId]
        }
      }
    ]
  }
  tags: tags
}

// Retrieve the Private DNS Zone
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  name: privateDnsZoneName
}

// Extract Private IP and FQDN
module privateIpExtractor 'vnetIpExtractor.bicep' = {
  name: 'extractPrivateIp-${name}'
  scope: resourceGroup('rg-central')
  params: {
    name: name
    privateEndpointId: privateEndpoint.id
    timeout: timeout
    serviceType: serviceType
    clientName: clientName
    discriminator: discriminator
    region: region
  }
}

// **🔧 Updated Deployment Script**
resource createDnsRecords 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-dns-records-${name}'
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
        value: join(privateIpExtractor.outputs.privateIps, '\n')
      }
      {
        name: 'PRIVATE_FQDNS'
        value: join(privateIpExtractor.outputs.privateFqdns, '\n')
      }
      {
        name: 'privateDnsZoneName'
        value: privateDnsZoneName
      }
    ]
    timeout: 'PT300S' // Keeping the timeout
    retentionInterval: 'P1D'
  }
  dependsOn: [
    privateIpExtractor
    privateDnsZone
  ]
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id

@description('The private IP addresses of the Private Endpoint')
output privateIps array = privateIpExtractor.outputs.privateIps

@description('The private FQDNs of the Private Endpoint')
output privateFqdns array = privateIpExtractor.outputs.privateFqdns
