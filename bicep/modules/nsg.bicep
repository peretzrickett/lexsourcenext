// modules/nsg.bicep

@description('Name of the client for the network security groups')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Geographic location for the network security groups')
param location string

@description('CIDR block for the Azure Front Door private IP range for secure access')
param frontDoorPrivateIp string

// Create Backend NSG to allow only VNet traffic for internal security
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
          description: 'Allow traffic within the virtual network for secure communication'
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
          description: 'Deny all other inbound traffic for security'
        }
      }
    ]
  }
}

// Create Frontend NSG to allow only Front Door private IP for secure inbound access
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
          description: 'Allow traffic from Azure Front Door private IP for secure access'
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
          description: 'Deny all other inbound traffic for security'
        }
      }
    ]
  }
}

// Create PrivateLink NSG to allow only Front Door private IP for secure private link access
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
          description: 'Allow traffic from Azure Front Door private IP for secure private link access'
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
          description: 'Deny all other inbound traffic for security'
        }
      }
    ]
  }
}

@description('Array of resource IDs for the network security groups created')
output nsgIds array = [
  frontendNsg.id
  backendNsg.id
  privatelinkNsg.id
]
