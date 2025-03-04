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
param dnsServers array

@description('Enable DNS proxy on the Azure Firewall')
param enableDnsProxy bool

@description('Private IP address of the VM for SSH access')
param vmPrivateIp string = '10.0.2.4'

@description('Array of client subnet configurations for firewall rules')
param clientSubnets array = []

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

// First create a firewall policy that includes the DNS settings
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2022-05-01' = {
  name: '${name}-policy'
  location: location
  properties: {
    dnsSettings: {
      servers: dnsServers
      enableProxy: enableDnsProxy
    }
    threatIntelMode: threatIntelMode
  }
}

// Create NAT Rule Collection Group for SSH access
resource natRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-05-01' = {
  parent: firewallPolicy
  name: 'DefaultNatRuleCollectionGroup'
  properties: {
    priority: 100
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        name: 'SSHAccess'
        priority: 100
        action: {
          type: 'DNAT'
        }
        rules: [
          {
            ruleType: 'NatRule'
            name: 'SSHToVM'
            sourceAddresses: ['*']
            destinationAddresses: [publicIp.properties.ipAddress]
            destinationPorts: ['22']
            ipProtocols: ['TCP']
            translatedAddress: vmPrivateIp
            translatedPort: '22'
          }
        ]
      }
    ]
  }
}

// Create client subnets network rules array
var clientSubnetRules = [for (subnet, i) in clientSubnets: {
  ruleType: 'NetworkRule'
  name: 'AllowToClient${i}'
  sourceAddresses: ['10.0.2.0/24'] // OtherServices subnet containing VM
  destinationAddresses: [subnet]
  ipProtocols: ['Any']
  destinationPorts: ['*']
}]

// Create a policy rule collection group to hold network rules
resource networkRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-05-01' = {
  parent: firewallPolicy
  name: 'DefaultNetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowDNSAndARMAndSSH'
        priority: 200
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowDNSResolver'
            sourceAddresses: ['10.0.2.0/24']  // OtherServices subnet
            destinationAddresses: ['168.63.129.16']
            ipProtocols: ['TCP', 'UDP']  // DNS uses both TCP and UDP on port 53
            destinationPorts: ['53']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowManagement'
            sourceAddresses: ['10.0.2.0/24']  // OtherServices subnet
            destinationAddresses: ['AzureResourceManager']
            ipProtocols: ['TCP']
            destinationPorts: ['443']
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowVMOutbound'
            sourceAddresses: ['10.0.2.0/24'] // OtherServices subnet containing VM
            destinationAddresses: ['*']      // Any destination
            ipProtocols: ['Any']            // Any protocol - TCP, UDP, ICMP 
            destinationPorts: ['*']          // Any port
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowAllProtocolsToClients'
            sourceAddresses: ['10.0.2.0/24'] // OtherServices subnet containing VM
            destinationAddresses: ['10.0.0.0/8'] // All clients in 10.x.x.x range
            ipProtocols: ['Any']  // Allow all protocols including TCP, UDP, ICMP
            destinationPorts: ['*']          // Any port
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowVPNInbound'
            sourceAddresses: ['*'] // Any source address for VPN clients
            destinationAddresses: ['10.0.3.0/26'] // Gateway Subnet with VPN Gateway
            ipProtocols: ['UDP', 'TCP'] // VPN protocols
            destinationPorts: ['500', '4500', '1701', '1723', '443'] // IKE, IKEv2, L2TP, PPTP, OpenVPN
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowVPNClientTraffic'
            sourceAddresses: ['172.16.0.0/24'] // VPN Client Address Pool
            destinationAddresses: ['*'] // All destinations
            ipProtocols: ['Any'] // All protocols
            destinationPorts: ['*'] // All ports
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowFromFrontDoor'
            sourceAddresses: ['10.8.0.0/16'] // Azure Front Door managed private endpoints
            destinationAddresses: ['10.0.0.0/8'] // All resources in your network
            ipProtocols: ['Any'] // All protocols
            destinationPorts: ['*'] // All ports
          }
          {
            ruleType: 'NetworkRule'
            name: 'AllowFrontDoorServiceTag'
            sourceAddresses: ['AzureFrontDoor.Backend'] // Azure Front Door service tag
            destinationAddresses: ['10.0.0.0/8'] // All resources in your network
            ipProtocols: ['Any'] // All protocols
            destinationPorts: ['*'] // All ports
          }
        ]
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'ClientSpecificRules'
        priority: 210
        action: {
          type: 'Allow'
        }
        rules: clientSubnetRules
      }
    ]
  }
  dependsOn: [
    natRuleCollectionGroup // Ensure NAT rules are created first
  ]
}

// Create application rules for web access
resource applicationRuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2022-05-01' = {
  parent: firewallPolicy
  name: 'DefaultApplicationRuleCollectionGroup'
  properties: {
    priority: 300
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        name: 'AllowWebAccess'
        priority: 300
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'AllowVPNClientsWeb'
            sourceAddresses: ['172.16.0.0/24'] // VPN Client Address Pool
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: ['*']
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AllowFrontDoorToWebApps'
            sourceAddresses: ['10.8.0.0/16'] // Azure Front Door managed private endpoints
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            targetFqdns: [
              '*.azurewebsites.net'
              '*.privatelink.azurewebsites.net'
            ]
          }
        ]
      }
    ]
  }
  dependsOn: [
    networkRuleCollectionGroup
  ]
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
    firewallPolicy: {
      id: firewallPolicy.id
    }
  }
  tags: tags
  dependsOn: [
    natRuleCollectionGroup
    networkRuleCollectionGroup
    applicationRuleCollectionGroup
  ]
}

@description('The resource ID of the Azure Firewall')
output id string = firewall.id

@description('The name of the Azure Firewall')
output name string = firewall.name

@description('The public IP configuration of the Azure Firewall')
output publicIp string = firewall.properties.ipConfigurations[0].properties.publicIPAddress.id

@description('The private IP of the Azure Firewall')
output privateIp string = firewall.properties.ipConfigurations[0].properties.privateIPAddress