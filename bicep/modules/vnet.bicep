param name string
param location string
param addressPrefixes array
param subnets array

resource vnet 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: addressPrefixes
    }
    subnets: [
      for subnet in subnets: {
        name: subnet.name
        properties: {
          addressPrefix: subnet.addressPrefix
        }
      }
    ]
  }
}

output id string = vnet.id

output subnets array = [
  for subnet in subnets: {
    name: subnet.name
    id: '${vnet.id}/subnets/${subnet.name}'
  }
]

output vnetId string = vnet.id
