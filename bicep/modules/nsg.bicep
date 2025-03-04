// modules/nsg.bicep

@description('Name of the client for the network security groups')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Geographic location for the network security groups')
param location string

@description('CIDR block for the Azure Front Door private IP range for secure access')
param frontDoorPrivateIp string = '10.0.0.0/16'

@description('CIDR block for the Azure Front Door managed private endpoints')
param afdManagedEndpointsCidr string = '10.8.0.0/16'

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
      // No Deny-All rule to allow proper functioning in a Hub-Spoke model
    ]
  }
}

// Create Frontend NSG to allow Front Door access
resource frontendNsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-${discriminator}-${clientName}-frontend'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Hub-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: frontDoorPrivateIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Hub VNet for secure access'
        }
      }
      {
        name: 'Allow-AFD-Managed-Endpoints'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: afdManagedEndpointsCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Azure Front Door managed private endpoints'
        }
      }
      {
        name: 'Allow-AFD-Service'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Azure Front Door service tag'
        }
      }
      // No Deny-All rule to allow proper functioning in a Hub-Spoke model
    ]
  }
}

// Create PrivateLink NSG with same rules as frontend
resource privatelinkNsg 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-${discriminator}-${clientName}-privatelink'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-Hub-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: frontDoorPrivateIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Hub VNet for secure access'
        }
      }
      {
        name: 'Allow-AFD-Managed-Endpoints'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: afdManagedEndpointsCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Azure Front Door managed private endpoints'
        }
      }
      {
        name: 'Allow-AFD-Service'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Allow traffic from Azure Front Door service tag'
        }
      }
      // No Deny-All rule to allow proper functioning in a Hub-Spoke model
    ]
  }
}

@description('Array of resource IDs for the network security groups created')
output nsgIds array = [
  frontendNsg.id
  backendNsg.id
  privatelinkNsg.id
]
