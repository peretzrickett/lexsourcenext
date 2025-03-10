# Azure Front Door to Private Endpoint Connectivity

This document summarizes the connectivity configurations implemented to ensure proper communication between Azure Front Door and private endpoints in the deployment.

## Overview of the Issue

When setting up Azure Front Door to communicate with App Services via private endpoints, connectivity issues can arise due to several factors:

1. Azure Front Door uses private managed endpoints (10.8.0.0/16) to connect to backend services
2. Traffic must flow properly through network security groups, route tables, and the Azure Firewall
3. Private DNS resolution must work correctly for the private endpoints

## Important SKU Requirements

### Azure Firewall Premium SKU

Azure Front Door Premium with Private Link integration requires Azure Firewall Premium SKU for proper functionality. The Standard SKU lacks some of the advanced networking capabilities required for this configuration.

```bicep
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2022-05-01' = {
  name: '${name}-policy'
  location: location
  properties: {
    // Other properties...
    sku: {
      tier: 'Premium'  // Required for Azure Front Door Premium with Private Link
    }
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2022-05-01' = {
  name: name
  location: location
  properties: {
    // Other properties...
    sku: {
      name: 'AZFW_VNet'
      tier: 'Premium'  // Required for Azure Front Door Premium with Private Link
    }
  }
}
```

The Premium SKU provides:
- Enhanced protocol handling for private connections
- Better TLS inspection capabilities
- Advanced threat protection features
- Improved support for complex networking scenarios

### App Service Plan Requirements

For optimal compatibility, the App Service Plan should be on a Premium v2 (P1v2) or higher tier when used with Azure Front Door Premium and Private Link.

## Implemented Solutions

### 1. Route Table Configuration

The central route table includes a specific route for the Azure Front Door private endpoint subnet:

```bicep
{
  name: 'RouteToFrontDoorPrivateLink'
  properties: {
    addressPrefix: '10.8.0.0/16'
    nextHopType: 'VirtualAppliance'
    nextHopIpAddress: firewall.outputs.privateIp
  }
}
```

This ensures all traffic to the Azure Front Door managed endpoint network is properly routed through the Azure Firewall.

### 2. Firewall Rules

Several rules were added to the Azure Firewall policy to allow the necessary traffic flows:

```bicep
// Allow VM to Front Door private endpoints
{
  ruleType: 'NetworkRule'
  name: 'AllowVMToFrontDoor'
  sourceAddresses: ['10.0.2.0/24'] // VM subnet
  destinationAddresses: ['10.8.0.0/16'] // Azure Front Door private endpoints
  ipProtocols: ['Any'] 
  destinationPorts: ['*']
}

// Allow VM to Front Door service tag
{
  ruleType: 'NetworkRule'
  name: 'AllowToFrontDoorServiceTag'
  sourceAddresses: ['10.0.2.0/24'] // VM subnet
  destinationAddresses: ['AzureFrontDoor.Backend'] // AFD service tag
  ipProtocols: ['Any']
  destinationPorts: ['*'] 
}

// Allow Firewall to Front Door service tag
{
  ruleType: 'NetworkRule'
  name: 'AllowFirewallToFrontDoorServiceTag'
  sourceAddresses: ['10.0.1.0/24'] // Firewall subnet
  destinationAddresses: ['AzureFrontDoor.Backend'] // AFD service tag
  ipProtocols: ['Any']
  destinationPorts: ['*']
}

// Allow Front Door to Private Endpoints
{
  ruleType: 'NetworkRule'
  name: 'AllowFrontDoorToPrivateEndpoint'
  sourceAddresses: ['10.8.0.0/16'] // Azure Front Door managed private endpoints 
  destinationAddresses: ['10.0.0.0/8'] // Include all private endpoint IPs in your network
  ipProtocols: ['Any'] // All protocols
  destinationPorts: ['*'] // All ports
}
```

Additional application rules were also added:

```bicep
// Allow VM to access web apps and Front Door
{
  ruleType: 'ApplicationRule'
  name: 'AllowVMToWebApps'
  sourceAddresses: ['10.0.2.0/24'] // VM subnet
  protocols: [
    {
      protocolType: 'Http'
      port: 80
    },
    {
      protocolType: 'Https'
      port: 443
    }
  ]
  targetFqdns: [
    '*.azurewebsites.net'
    '*.privatelink.azurewebsites.net'
    '*.azurefd.net'
  ]
}

// Allow Front Door to access private endpoints via HTTP/HTTPS
{
  ruleType: 'ApplicationRule'
  name: 'AllowFrontDoorToPrivateEndpoints'
  sourceAddresses: ['10.8.0.0/16'] // Azure Front Door managed private endpoints
  protocols: [
    {
      protocolType: 'Http'
      port: 80
    },
    {
      protocolType: 'Https'
      port: 443
    }
  ]
  targetFqdns: [
    '*.privatelink.azurewebsites.net'
    '10.*.*.* ' // All private IP addresses in the 10.0.0.0/8 range
  ]
}
```

### 3. Network Security Group Rules

The NSG rules for the private link subnet were updated to allow proper traffic flow:

```bicep
{
  name: 'Allow-Hub-VNet'
  properties: {
    priority: 100
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefix: frontDoorPrivateIp
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
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
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
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
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
  }
}

{
  name: 'Allow-Central-VNet'
  properties: {
    priority: 130
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefix: '10.0.0.0/16'  // Central VNet
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
  }
}

{
  name: 'Allow-AFD-Frontend'
  properties: {
    priority: 140
    direction: 'Inbound'
    access: 'Allow'
    protocol: '*'
    sourceAddressPrefix: 'AzureFrontDoor.Frontend'
    destinationAddressPrefix: '*'
    destinationPortRange: '*'
  }
}
```

### 4. Private Link Approval Process

The private link approval process was enhanced in the `frontDoorConfigure.bicep` script:

1. The script creates origins with private links to the app services
2. It then includes logic to approve the private endpoint connections from both sides:
   - From the Front Door origin side
   - From the App Service private endpoint side

## Testing Connectivity

After implementing these changes, connectivity can be tested using the following commands:

1. SSH to the network tester VM:
   ```bash
   ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@<vm-ip>
   ```

2. Test connectivity to the Front Door endpoint:
   ```bash
   curl -k https://<afd-endpoint-name>.azurefd.net
   ```

3. Check DNS resolution for the private endpoints:
   ```bash
   nslookup app-<discriminator>-<client>.privatelink.azurewebsites.net
   ```

## Troubleshooting Remaining Issues

If connectivity issues persist after implementing these changes, consider checking:

1. **SKU Requirements**: Ensure Azure Firewall is using the Premium SKU and App Service Plan is using at least the Premium V2 tier.

2. **NSG Flow Logs**: Enable NSG flow logs to see if traffic is being blocked

3. **Azure Firewall Logs**: Check if the firewall is blocking or allowing the traffic

4. **Private DNS Resolution**: Ensure private DNS zones have the correct records

5. **Network Watcher**: Use Network Watcher to test connectivity between resources

6. **Deployment Status**: Azure Front Door deployments with private link can take 10-20 minutes to fully propagate through the network.

## SKU Verification Commands

Use these commands to verify the SKUs of your resources:

```bash
# Check Azure Firewall SKU
az network firewall show --name globalFirewall --resource-group rg-central --query "sku"

# Check App Service Plan SKU 
az appservice plan show --name asp-<discriminator>-<client> --resource-group rg-<client> --query "sku"
```

## Additional Resources

- [Azure Front Door with Private Link Service](https://learn.microsoft.com/en-us/azure/frontdoor/private-link)
- [Private Link for Azure App Service](https://learn.microsoft.com/en-us/azure/app-service/networking/private-endpoint)
- [Azure Firewall Network Rules](https://learn.microsoft.com/en-us/azure/firewall/features)
- [Network Security Group Overview](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview)
- [Azure Firewall Premium Features](https://learn.microsoft.com/en-us/azure/firewall/premium-features)
- [Azure Firewall SKU Comparison](https://learn.microsoft.com/en-us/azure/firewall/overview#azure-firewall-standard-and-premium)
- [App Service Plans SKU Options](https://learn.microsoft.com/en-us/azure/app-service/overview-hosting-plans) 