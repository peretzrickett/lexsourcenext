#\!/bin/bash
# Generate a simple VPN client certificate for P2S VPN connection

set -e

# Settings
PASSWORD="Password123"
CERT_FILE="vpn-client-new.pfx"

# Generate a new private key
openssl genrsa -out client.key 2048

# Generate a self-signed certificate
openssl req -new -x509 -key client.key -out client.crt -days 365 -subj "/CN=VpnClientCert"

# Create a PKCS#12 bundle
openssl pkcs12 -export -out "$CERT_FILE" -inkey client.key -in client.crt -password pass:"$PASSWORD"

# Cleanup temporary files
rm client.key client.crt

echo "Created new client certificate: $CERT_FILE"
echo "Password: $PASSWORD"
echo ""
echo "To use this certificate with the VPN:"
echo "1. Import the certificate into your personal certificate store"
echo "2. Download the VPN client configuration package using:"
echo "   az network vnet-gateway vpn-client generate --resource-group rg-central --name vpngw-lexsb"
echo "3. Extract and install the VPN client configuration"
echo "4. Connect using the Azure VPN client"
