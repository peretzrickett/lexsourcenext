// modules/vpn.bicep
// Point-to-Site VPN Gateway implementation for private network connectivity

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Azure region where resources will be deployed')
param location string

@description('Address pool for VPN clients, e.g. 172.16.0.0/24')
param addressPool string

@description('Authentication type for VPN clients')
@allowed([
  'Certificate'
  'AAD'
])
param authType string = 'Certificate'

@description('Root certificate data for VPN authentication (base64-encoded .cer)')
param rootCertData string = ''

@description('Root certificate name for VPN authentication')
param rootCertName string = 'P2SRootCert'

@description('Azure AD tenant ID for AAD authentication')
param aadTenantId string = ''

@description('Azure AD audience for AAD authentication')
param aadAudience string = ''

@description('Azure AD issuer for AAD authentication')
param aadIssuer string = ''

// Reference the existing central VNet
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: 'vnet-${discriminator}-central'
}

// Check if GatewaySubnet exists, if not, create it
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  name: 'GatewaySubnet'
  parent: vnet
}

// Public IP for the VPN Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'vpngw-pip-${discriminator}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'vpn-${toLower(discriminator)}'
    }
  }
}

// VPN Server Configuration for P2S VPN
resource vpnServerConfig 'Microsoft.Network/vpnServerConfigurations@2023-05-01' = {
  name: 'vpnconfig-${discriminator}'
  location: location
  properties: {
    vpnProtocols: [
      'IkeV2'
      'OpenVPN'
    ]
    vpnAuthenticationTypes: [
      authType
    ]
    vpnClientRootCertificates: authType == 'Certificate' ? [
      {
        name: rootCertName
        publicCertData: rootCertData
      }
    ] : []
    aadAuthenticationParameters: authType == 'AAD' ? {
      aadTenant: aadTenantId
      aadAudience: aadAudience
      aadIssuer: aadIssuer
    } : null
  }
}

// Virtual Network Gateway for P2S VPN
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
  name: 'vpngw-${discriminator}'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    sku: {
      name: 'VpnGw2'
      tier: 'VpnGw2'
    }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnet.id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          addressPool
        ]
      }
      vpnClientProtocols: [
        'IkeV2'
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        authType
      ]
      vpnClientRootCertificates: authType == 'Certificate' ? [
        {
          name: rootCertName
          publicCertData: rootCertData
        }
      ] : []
      aadTenant: authType == 'AAD' ? aadTenantId : null
      aadAudience: authType == 'AAD' ? aadAudience : null
      aadIssuer: authType == 'AAD' ? aadIssuer : null
    }
  }
}

@description('The resource ID of the VPN gateway')
output vpnGatewayId string = vpnGateway.id

@description('The public IP address of the VPN gateway')
output vpnPublicIpAddress string = publicIp.properties.ipAddress

@description('The VPN client configuration package URL')
output vpnClientPackageUrl string = '${subscription().tenantId}/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworkGateways/${vpnGateway.name}/vpnclientpackage'
