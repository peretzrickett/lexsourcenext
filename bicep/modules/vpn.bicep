param discriminator string
param location string
param addressPool string

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: 'vnet-${discriminator}-Central'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: 'GatewaySubnet'
  parent: vnet
}

// VPN Gateway (without P2S config, only for site-to-site)
resource vpnGateway 'Microsoft.Network/vpnGateways@2023-02-01' = {
  name: 'vpngw-${discriminator}'
  location: location
  properties: {
    virtualHub: null
    vpnGatewayScaleUnit: 1
    bgpSettings: null
    isRoutingPreferenceInternet: false
    connections: []
  }
  dependsOn: [subnet, publicIp]
}

// ✅ Correct way to define P2S VPN separately
resource p2sVpnGateway 'Microsoft.Network/p2sVpnGateways@2023-02-01' = {
  name: 'p2s-vpngw-${discriminator}'
  location: location
  properties: {
    vpnServerConfiguration: {
      id: vpnGateway.id
    }
    p2SConnectionConfigurations: [
      {
        name: 'p2sConfig'
        properties: {
          vpnClientAddressPool: {
            addressPrefixes: [addressPool]
          }
          enableInternetSecurity: false
          // vpnAuthTypes: ['AAD'] // Use 'Certificate' if needed
        }
      }
    ]
  }
  dependsOn: [vpnGateway]
}

resource vpnGwIpConfig 'Microsoft.Network/vpnGateways/ipConfigurations@2023-02-01' = {
  name: 'default'
  parent: vpnGateway
  properties: {
    publicIPAddress: {
      id: publicIp.id
    }
    subnet: {
      id: subnet.id
    }
  }
}

// Public IP for the VPN Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: 'vpngw-pip-${discriminator}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
