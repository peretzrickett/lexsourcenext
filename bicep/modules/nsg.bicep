
param clientName string
param discriminator string
param location string
param frontDoorPrivateIp string

// Create Backend NSG (Allow only VNet traffic)
resource backendNsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-${discriminator}-${clientName}-backend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-VNet-Traffic'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Create Frontend NSG (Allow only Front Door Private IP)
resource frontendNsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-${discriminator}-${clientName}-frontend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-FrontDoor-Private-IP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: frontDoorPrivateIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// Create Frontend NSG (Allow only Front Door Private IP)
resource privatelinkNsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-${discriminator}-${clientName}-privatelink'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-FrontDoor-Private-IP'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: frontDoorPrivateIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
//   name: 'vnet-${discriminator}-${clientName}'
// }

// resource frontEndSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
//   name: 'FrontEnd'
//   parent: vnet
// }

// resource backEndSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
//   name: 'BackEnd'
//   parent: vnet
// }

// // Associate NSGs with Subnets
// resource backendSubnetNsgAssoc 'Microsoft.Network/virtualNetworks/subnets/networkSecurityGroup@2023-02-01' = {
//   name: 'backend-nsg-association'
//   parent: backEndSubnet
//   properties: {
//     id: backendNsg.id
//   }
// }

// resource frontendSubnetNsgAssoc 'Microsoft.Network/virtualNetworks/subnets/networkSecurityGroup@2023-02-01' = {
//   name: 'frontend-nsg-association'
//   parent: frontEndSubnet
//   properties: {
//     id: frontendNsg.id
//   }
// }

output nsgIds array = [
  frontendNsg.id
  backendNsg.id
  privatelinkNsg.id
]
