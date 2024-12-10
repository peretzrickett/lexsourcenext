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

@description('Firewall policy ID (optional)')
param firewallPolicyId string = ''

@description('Tags to apply to the Azure Firewall')
param tags object = {}

resource publicIp 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'ip${name}'
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
        name: '${name}-ipconfig'
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
    firewallPolicy: empty(firewallPolicyId) ? null : {
      id: firewallPolicyId
    }
  }
  tags: tags
}

@description('The resource ID of the Azure Firewall')
output id string = firewall.id

@description('The name of the Azure Firewall')
output name string = firewall.name

@description('The public IP configuration of the Azure Firewall')
output publicIp string = firewall.properties.ipConfigurations[0].properties.publicIPAddress.id
