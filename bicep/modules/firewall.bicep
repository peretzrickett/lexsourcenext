param name string
param location string
param vnetId string

resource firewall 'Microsoft.Network/azureFirewalls@2021-05-01' = {
  name: name
  location: location
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

output id string = firewall.id
