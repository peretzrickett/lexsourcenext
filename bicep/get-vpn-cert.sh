#!/bin/bash
# Helper script to retrieve VPN client certificate from Key Vault

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Central resource group name
CENTRAL_RG="rg-${DISCRIMINATOR}-central"

set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KV_NAME="kv-${DISCRIMINATOR}-central"
PFX_OUTPUT="vpn-client.pfx"

# Try to get the timestamp from Key Vault
echo -e "${YELLOW}Checking for certificate timestamp...${NC}"
TIMESTAMP=$(az keyvault secret show --vault-name $KV_NAME --name "vpn-cert-timestamp" --query "value" -o tsv 2>/dev/null || echo "")

if [ -n "$TIMESTAMP" ]; then
  echo -e "${GREEN}Found certificate timestamp: $TIMESTAMP${NC}"
  CLIENT_CERT_NAME="P2SClientCert-$TIMESTAMP"
else
  echo -e "${YELLOW}No timestamp found, using default certificate name${NC}"
  CLIENT_CERT_NAME="P2SClientCert"
fi

echo -e "${YELLOW}Retrieving VPN client certificate from Key Vault...${NC}"

# Check if the current user has access to Key Vault
echo -e "${YELLOW}Checking Key Vault access...${NC}"
if ! az keyvault list --query "[?name=='$KV_NAME'].name" -o tsv &>/dev/null; then
  echo -e "${RED}Error: Cannot access Key Vault $KV_NAME${NC}"
  echo -e "${YELLOW}Assigning yourself Key Vault Administrator role...${NC}"
  
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  USER_ID=$(az ad signed-in-user show --query id -o tsv)
  KV_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/${CENTRAL_RG}/providers/Microsoft.KeyVault/vaults/$KV_NAME"
  
  # Assign Key Vault Administrator role
  echo -e "${YELLOW}Creating role assignment...${NC}"
  az role assignment create --assignee "$USER_ID" --role "Key Vault Administrator" --scope "$KV_SCOPE"
  
  # Wait for permission propagation
  echo -e "${YELLOW}Waiting for permissions to propagate...${NC}"
  sleep 15
  
  # Check if we can now access the Key Vault
  if ! az keyvault list --query "[?name=='$KV_NAME'].name" -o tsv &>/dev/null; then
    echo -e "${RED}Still cannot access Key Vault. Please ensure you have proper permissions.${NC}"
    echo -e "${YELLOW}You may need to assign yourself Key Vault Administrator, Secret Officer, or Reader roles manually:${NC}"
    echo -e "az role assignment create --assignee <your-email> --role \"Key Vault Administrator\" --scope $KV_SCOPE"
    exit 1
  fi
  
  echo -e "${GREEN}Successfully assigned Key Vault permissions!${NC}"
fi

# Get client certificate from Key Vault
echo -e "${YELLOW}Retrieving client certificate from Key Vault...${NC}"
echo -e "${YELLOW}Looking for certificate: $CLIENT_CERT_NAME-pfx${NC}"

if az keyvault secret show --vault-name $KV_NAME --name "$CLIENT_CERT_NAME-pfx" --query "value" -o tsv 2>/dev/null > client_cert_b64.txt; then
  echo -e "${GREEN}Found client certificate in Key Vault!${NC}"
  cat client_cert_b64.txt | base64 -d > $PFX_OUTPUT
  PASSWORD=$(az keyvault secret show --vault-name $KV_NAME --name "$CLIENT_CERT_NAME-password" --query "value" -o tsv)
  echo -e "${GREEN}Password: $PASSWORD${NC}"
else
  echo -e "${RED}Certificate not found in Key Vault.${NC}"
  echo -e "${YELLOW}Please run the VPN deployment again or ensure the certificate exists in Key Vault.${NC}"
  exit 1
fi

# Get the VPN client configuration package URL directly from the gateway
echo -e "${YELLOW}Getting VPN client configuration package URL...${NC}"
VPN_URL=$(az network vnet-gateway vpn-client show-url --resource-group ${CENTRAL_RG} --name vpngw-${DISCRIMINATOR} --query "value" -o tsv)

if [ -n "$VPN_URL" ]; then
  echo -e "${GREEN}VPN client configuration package URL:${NC}"
  echo "$VPN_URL"
else
  echo -e "${RED}Could not get VPN client configuration package URL.${NC}"
  echo -e "${YELLOW}Please check if the VPN gateway is deployed correctly.${NC}"
  exit 1
fi

echo -e "${GREEN}VPN client certificate saved to ${PFX_OUTPUT}${NC}"
echo -e "${YELLOW}Instructions for VPN setup:${NC}"
echo -e "1. Download the VPN client configuration package from the URL above"
echo -e "2. Extract the package and find the appropriate configuration for your system"
echo -e "3. Install the VPN client configuration"
echo -e "4. Install the client certificate ($PFX_OUTPUT) using the password provided"
echo -e "5. Connect to the VPN using the Azure VPN client"

# Clean up
rm -f client_cert_b64.txt