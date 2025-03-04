# Point-to-Site VPN Gateway for Private Network Access

This document explains how to set up and use the Point-to-Site (P2S) VPN solution for secure remote access to the private network.

## Overview

The VPN solution provides secure access to resources deployed in the private network environment by:

1. Deploying an Azure VPN Gateway in the central resource group
2. Automatically generating and storing certificates in Key Vault (or using your own)
3. Creating and configuring VPN client configuration packages
4. Establishing connectivity to the private network with proper routing

## Deployment

The VPN Gateway is deployed automatically as part of the main Bicep deployment unless specifically disabled.

### Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `deployVpn` | Whether to deploy the VPN Gateway | `true` |
| `vpnRootCertName` | Certificate name for VPN authentication | `P2SRootCert` |
| `vpnRootCertData` | Certificate data (base64-encoded .cer file) | Auto-generated if empty |

### Deployment Options

**Option 1: Automatic Certificate Generation**

```bash
./go.sh
```

The deployment will automatically:
- Create a VPN Gateway in the central VNet
- Generate a self-signed certificate
- Store the certificate in Key Vault
- Configure the gateway with the certificate

**Option 2: Use Your Own Certificate**

```bash
# Generate root certificate locally
openssl genrsa -out P2SRootCert.key 2048
openssl req -new -key P2SRootCert.key -out P2SRootCert.csr -subj "/CN=P2SRootCert"
openssl x509 -req -days 3650 -in P2SRootCert.csr -signkey P2SRootCert.key -out P2SRootCert.cer
BASE64_CERT=$(base64 -i P2SRootCert.cer | tr -d '\n')

# Deploy with your certificate
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters @clients.json \
  --parameters vpnRootCertData=$BASE64_CERT
```

## Connecting to the VPN

### 1. Download the VPN Client Configuration

After deployment, retrieve the VPN client configuration package URL:

```bash
# Get Resource Group name
RG_NAME="rg-central"

# Get VPN Gateway name
VPN_GW_NAME=$(az network vnet-gateway list --resource-group $RG_NAME --query "[0].name" -o tsv)

# Download VPN client configuration
az network vnet-gateway vpn-client generate \
  --resource-group $RG_NAME \
  --name $VPN_GW_NAME \
  --authentication-method EAPTLS
```

### 2. Install the VPN Client

1. Extract the downloaded ZIP file
2. Follow the installation instructions for your platform:
   - **Windows**: Run the included installer
   - **macOS**: Import the profile in Network Settings
   - **Linux**: Use the OpenVPN configuration files

### 3. Connect to the VPN

* **Windows**: Use the Azure VPN Client or native Windows VPN
* **macOS**: Use Tunnelblick or the native macOS VPN client
* **Linux**: Use OpenVPN

## Key Components

1. **VPN Gateway**
   - Deployed in the hub virtual network in the GatewaySubnet
   - Uses certificate-based authentication
   - Supports IKEv2 and OpenVPN protocols

2. **Client Certificate Management**
   - Auto-generation or manual creation of certificates
   - Root certificate is uploaded to the VPN Gateway configuration
   - Client certificate is used for user authentication

3. **Network Connectivity**
   - Clients get IP addresses from the 172.16.0.0/24 range
   - All traffic to private subnets is routed through the VPN
   - Access to Azure resources through private endpoints

## Usage for Development

Developers should connect to the VPN to:

1. Access web applications through private endpoints
2. Connect to SQL databases directly using private DNS names
3. Deploy code to services that aren't accessible publicly
4. Access resources through Azure Front Door for testing

## Troubleshooting

### Connection Issues

1. **Certificate Problems**:
   - Ensure the client certificate is derived from the root certificate
   - Check Key Vault to verify the certificate was stored correctly

2. **Routing Issues**:
   - Verify the Azure Firewall allows VPN traffic (UDP 1194, TCP 443)
   - Check that the VPN address pool doesn't overlap with other subnets

3. **Gateway Status**:
   ```bash
   az network vnet-gateway show \
     --resource-group rg-central \
     --name vpngw-<discriminator> \
     --query "provisioningState"
   ```

## Security Considerations

* The VPN Gateway uses certificate-based authentication for secure access
* All connections are encrypted using IKEv2 or OpenVPN
* Client certificates should be kept secure and not shared
* Certificate can be revoked if compromised
* VPN access is logged and can be monitored in Azure Monitor