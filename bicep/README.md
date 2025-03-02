# VPN Gateway for Private Access

This section of the project implements a Point-to-Site (P2S) VPN Gateway for secure access to resources in the private virtual network.

## VPN Architecture

The VPN Gateway is deployed in the central hub virtual network and allows authenticated users to connect securely to:

- Web applications in client virtual networks
- SQL databases with private endpoints
- Storage accounts and other private resources

## Key Components

1. **VPN Gateway**
   - Deployed in the hub virtual network in the GatewaySubnet
   - Uses certificate-based authentication
   - Supports IKEv2 and OpenVPN protocols

2. **Client Certificate Generation**
   - Script for generating self-signed root and client certificates
   - Root certificate is uploaded to the VPN Gateway configuration
   - Client certificate is used for user authentication

3. **Network Connectivity**
   - Clients get IP addresses from the 172.16.0.0/24 range
   - All traffic to private subnets is routed through the VPN
   - Access to Azure resources through private endpoints

## Deployment

### Generate Certificates

Run the certificate generation script:

```bash
./generate-vpn-cert.sh
```

This will create:
- A root certificate for the VPN Gateway
- A client certificate for user connections

### Deploy VPN Gateway

Deploy the VPN Gateway with the generated certificate:

```bash
./deploy-vpn.sh
```

**Note:** VPN Gateway deployment takes approximately 30-45 minutes to complete.

### Connect to VPN

1. Download the VPN client configuration package from Azure Portal
2. Install the VPN client on your device
3. Import the client certificate (`certificates/P2SClientCert.pfx`)
4. Connect to the VPN to access resources securely

## Usage for Development

Developers should connect to the VPN to:

1. Access web applications through private endpoints
2. Connect to SQL databases directly using private DNS names
3. Deploy code to services that aren't accessible publicly
4. Access resources through Azure Front Door for testing

## Security Considerations

- The VPN Gateway uses certificate-based authentication for secure access
- All connections are encrypted using IKEv2 or OpenVPN
- Client certificates should be kept secure and not shared
- Certificate can be revoked if compromised
- VPN access is logged and can be monitored in Azure Monitor