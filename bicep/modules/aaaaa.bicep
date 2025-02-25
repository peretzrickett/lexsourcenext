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
      echo "Starting Private DNS Record Creation Script..."

      # Read IPs and FQDNs from input variables
      PRIVATE_IPS="${PRIVATE_IPS}"
      PRIVATE_FQDNS="${PRIVATE_FQDNS}"
      RESOURCE_GROUP="${RESOURCE_GROUP}"
      DNS_ZONE_NAME="${privateDnsZoneName}"

      # Split IPs and FQDNs into arrays
      IFS=$'\n' read -r -d '' -a ip_array <<< "$PRIVATE_IPS"
      IFS=$'\n' read -r -d '' -a fqdn_array <<< "$PRIVATE_FQDNS"

      echo "Extracted ${#ip_array[@]} private IP(s) and ${#fqdn_array[@]} FQDN(s)."
      echo "Private IPs: ${ip_array[*]}"
      echo "Private FQDNs: ${fqdn_array[*]}"

      for fqdn in "${fqdn_array[@]}"; do
          record_name=$(echo "$fqdn" | sed "s/.${DNS_ZONE_NAME}//")  # Extract subdomain only
          echo "Processing DNS record: $record_name"

          for ip in "${ip_array[@]}"; do
              echo "Creating A record for $record_name -> $ip"
              az network private-dns record-set a create \
                --resource-group "$RESOURCE_GROUP" \
                --zone-name "$DNS_ZONE_NAME" \
                --name "$record_name" \
                --ttl 3600 || {
                  echo "Error: Failed to create A record for $record_name"
                  exit 1
              }

              az network private-dns record-set a add-record \
                --resource-group "$RESOURCE_GROUP" \
                --zone-name "$DNS_ZONE_NAME" \
                --record-set-name "$record_name" \
                --ipv4-address "$ip" || {
                  echo "Error: Failed to add IP $ip to A record for $record_name"
                  exit 1
              }
          done
      done

      echo "DNS records successfully created!"
      echo "{\"privateDnsRecords\": \"Created A records for ${#fqdn_array[@]} FQDNs and ${#ip_array[@]} IPs\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'PRIVATE_IPS', value: join(privateIpExtractor.outputs.privateIps, '\n') }
      { name: 'PRIVATE_FQDNS', value: join(privateIpExtractor.outputs.privateFqdns, '\n') }
      { name: 'privateDnsZoneName', value: privateDnsZoneName }
    ]
    timeout: 'PT${timeout}S'
    retentionInterval: 'P1D'
  }
  dependsOn: [
    privateIpExtractor
    privateDnsZone
    privateEndpoint
  ]
}

@description('The resource ID of the Private Endpoint')
output id string = privateEndpoint.id

@description('The private IP addresses of the Private Endpoint')
output privateIps array = privateIpExtractor.outputs.privateIps

@description('The private FQDNs of the Private Endpoint')
output privateFqdns array = privateIpExtractor.outputs.privateFqdns
