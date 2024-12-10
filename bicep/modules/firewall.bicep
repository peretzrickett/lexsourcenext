param name string
param location string
param subnetId string

resource firewall 'Microsoft.Network/azureFirewalls@2021-05-01' = {
  name: name
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'azureFirewallIpConfiguration'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

output id string = firewall.id
