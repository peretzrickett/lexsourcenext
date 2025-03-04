#!/bin/bash
# Script to generate VPN certificates directly and store them in Key Vault

set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CERT_NAME="P2SRootCert"
CLIENT_CERT_NAME="P2SClientCert"
PASSWORD="Password1!"
KV_NAME="kv-lexsb-central"
TEMP_DIR=$(mktemp -d)

echo -e "${YELLOW}Generating VPN certificates and storing in Key Vault ${KV_NAME}...${NC}"

# Make sure we have access to the Key Vault
echo -e "${YELLOW}Setting Key Vault access policy...${NC}"
USER_ID=$(az ad signed-in-user show --query id -o tsv)
az keyvault set-policy --name $KV_NAME \
  --object-id $USER_ID \
  --certificate-permissions get list create import delete \
  --secret-permissions get list set delete \
  --key-permissions get list create delete

cd $TEMP_DIR

# Generate root certificate
echo -e "${YELLOW}Generating root certificate...${NC}"
openssl req -x509 -new -nodes -sha256 -days 3650 \
  -subj "/CN=$CERT_NAME" \
  -keyout "$CERT_NAME.key" \
  -out "$CERT_NAME.crt"

# Convert root cert to DER for Azure VPN
openssl x509 -in "$CERT_NAME.crt" -outform der -out "$CERT_NAME.cer"

# Base64 encode for Azure
ROOT_CERT_DATA=$(base64 -i "$CERT_NAME.cer" | tr -d '\n')

# Generate client key
echo -e "${YELLOW}Generating client certificate...${NC}"
openssl genrsa -out "$CLIENT_CERT_NAME.key" 2048

# Generate client certificate request
openssl req -new -key "$CLIENT_CERT_NAME.key" -out "$CLIENT_CERT_NAME.csr" -subj "/CN=$CLIENT_CERT_NAME"

# Sign client certificate with root certificate
openssl x509 -req -in "$CLIENT_CERT_NAME.csr" \
  -CA "$CERT_NAME.crt" \
  -CAkey "$CERT_NAME.key" \
  -CAcreateserial \
  -out "$CLIENT_CERT_NAME.crt" \
  -days 365 -sha256

# Create PKCS#12 file for client import
echo -e "${YELLOW}Creating PKCS#12 bundle...${NC}"
openssl pkcs12 -export \
  -in "$CLIENT_CERT_NAME.crt" \
  -inkey "$CLIENT_CERT_NAME.key" \
  -certfile "$CERT_NAME.crt" \
  -out "$CLIENT_CERT_NAME.pfx" \
  -password pass:$PASSWORD

# Create PFX for Key Vault root cert
openssl pkcs12 -export -out "$CERT_NAME.pfx" -inkey "$CERT_NAME.key" -in "$CERT_NAME.crt" -passout pass:$PASSWORD

# Store in Key Vault
echo -e "${YELLOW}Storing certificates in Key Vault...${NC}"

# Import root certificate
echo -e "${YELLOW}Importing root certificate...${NC}"
az keyvault certificate import --vault-name $KV_NAME \
  --name $CERT_NAME \
  --file "$CERT_NAME.pfx" \
  --password $PASSWORD

# Store public part of root certificate (needed for VPN Gateway)
echo -e "${YELLOW}Storing root certificate public data...${NC}"
az keyvault secret set --vault-name $KV_NAME \
  --name "$CERT_NAME-public" \
  --value "$ROOT_CERT_DATA"

# Import client certificate
echo -e "${YELLOW}Importing client certificate...${NC}"
az keyvault certificate import --vault-name $KV_NAME \
  --name $CLIENT_CERT_NAME \
  --file "$CLIENT_CERT_NAME.pfx" \
  --password $PASSWORD

# Store client certificate as a secret for easy download
echo -e "${YELLOW}Storing client PFX...${NC}"
CLIENT_PFX_B64=$(base64 -i "$CLIENT_CERT_NAME.pfx" | tr -d '\n')
az keyvault secret set --vault-name $KV_NAME \
  --name "$CLIENT_CERT_NAME-pfx" \
  --value "$CLIENT_PFX_B64"

# Store client certificate password
echo -e "${YELLOW}Storing client certificate password...${NC}"
az keyvault secret set --vault-name $KV_NAME \
  --name "$CLIENT_CERT_NAME-password" \
  --value "$PASSWORD"

echo -e "${YELLOW}Verifying certificates and secrets in Key Vault...${NC}"
echo -e "${YELLOW}Certificates:${NC}"
az keyvault certificate list --vault-name $KV_NAME --query "[].name" -o tsv

echo -e "${YELLOW}Secrets:${NC}"
az keyvault secret list --vault-name $KV_NAME --query "[].name" -o tsv

# Clean up
rm -rf $TEMP_DIR

echo -e "${GREEN}VPN certificates generated and stored in Key Vault successfully!${NC}"
echo -e "${YELLOW}To download the client certificate:${NC}"
echo -e "${YELLOW}az keyvault secret show --vault-name $KV_NAME --name $CLIENT_CERT_NAME-pfx --query value -o tsv | base64 -d > client-vpn.pfx${NC}"
echo -e "${YELLOW}Password for the client certificate:${NC}"
echo -e "${YELLOW}az keyvault secret show --vault-name $KV_NAME --name $CLIENT_CERT_NAME-password --query value -o tsv${NC}"