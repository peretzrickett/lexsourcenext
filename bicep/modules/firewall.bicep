@description('Name of the Azure Firewall')
param name string

@description('Location where the Azure Firewall will be deployed')
param location string

@description('Subnet ID where the Azure Firewall will be deployed')
param subnetId string

@description('Threat intelligence mode for the Azure Firewall')
@allowed([
  'Off'
  'Alert'
  'Deny'
])
param threatIntelMode string = 'Alert'

@description('DNS servers for the Azure Firewall')
param dnsServers array = ['168.63.129.16']

@description('Enable DNS proxy on the Azure Firewall')
param enableDnsProxy bool = true

@description('Tags to apply to the Azure Firewall')
param tags object = {}

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'ip-${name}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2022-05-01' = {
  name: name
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig-${name}'
        properties: {
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    threatIntelMode: threatIntelMode
    networkRuleCollections: [
      {
        name: 'AllowDNSAndARMAndSSH'
        properties: {
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'AllowDNSResolver'
              sourceAddresses: ['10.0.2.0/24']  // OtherServices subnet
              destinationAddresses: ['168.63.129.16']
              protocols: ['TCP', 'UDP']  // DNS uses both TCP and UDP on port 53
              destinationPorts: ['53']
            }
            {
              name: 'AllowManagement'
              sourceAddresses: ['10.0.2.0/24']  // OtherServices subnet
              destinationAddresses: ['AzureResourceManager']
              protocols: ['TCP']
              destinationPorts: ['443']
            }
            {
              name: 'AllowSSHInbound'
              sourceAddresses: ['*']
              destinationAddresses: ['172.174.206.65']  // VM public IP (update if changed)
              protocols: ['TCP']
              destinationPorts: ['22']
            }
          ]
        }
      }
    ]
  }
  tags: tags
}

@description('The resource ID of the Azure Firewall')
output id string = firewall.id

@description('The name of the Azure Firewall')
output name string = firewall.name

@description('The public IP configuration of the Azure Firewall')
output publicIp string = firewall.properties.ipConfigurations[0].properties.publicIPAddress.id

@description('The private IP of the Azure Firewall')
output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress
