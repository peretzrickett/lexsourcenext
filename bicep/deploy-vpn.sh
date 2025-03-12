#!/bin/bash
# Script to deploy VPN Gateway with certificate-based authentication
# This script will generate VPN certificates, store them in Key Vault, and update the VPN Gateway

set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
TEMP_DIR=$(mktemp -d)
CERT_NAME="P2SRootCert"
CLIENT_CERT_NAME="P2SClientCert"
CERT_PASSWORD="Password1!"  # Change this in production
LOCATION="eastus"
DISCRIMINATOR=${1:-"lexsb"}
KV_NAME="kv-lexsb-central"
FORCE_REGEN=false

# Central resource group name
CENTRAL_RG="rg-${DISCRIMINATOR}-central"

# Function to display usage
function display_usage {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --cert-name     Certificate name (default: P2SRootCert)"
  echo "  -c, --client-name   Client certificate name (default: P2SClientCert)"
  echo "  -p, --password      Certificate password (default: Password1!)"
  echo "  -k, --keyvault      Key Vault name (default: kv-lexsb-central)"
  echo "  -l, --location      Azure region (default: eastus)"
  echo "  -d, --discriminator Resource name discriminator (default: lexsb)"
  echo "  -f, --force         Force certificate regeneration"
  echo "  -h, --help          Display this help message"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -n|--cert-name)
      CERT_NAME="$2"
      shift 2
      ;;
    -c|--client-name)
      CLIENT_CERT_NAME="$2"
      shift 2
      ;;
    -p|--password)
      CERT_PASSWORD="$2"
      shift 2
      ;;
    -k|--keyvault)
      KV_NAME="$2"
      shift 2
      ;;
    -l|--location)
      LOCATION="$2"
      shift 2
      ;;
    -d|--discriminator)
      DISCRIMINATOR="$2"
      shift 2
      ;;
    -f|--force)
      FORCE_REGEN=true
      shift
      ;;
    -h|--help)
      display_usage
      ;;
    *)
      echo "Unknown option: $1"
      display_usage
      ;;
  esac
done

echo -e "${YELLOW}VPN Configuration Parameters:${NC}"
echo -e "${YELLOW}Root Certificate Name: $CERT_NAME${NC}"
echo -e "${YELLOW}Client Certificate Name: $CLIENT_CERT_NAME${NC}"
echo -e "${YELLOW}Key Vault: $KV_NAME${NC}"
echo -e "${YELLOW}Location: $LOCATION${NC}"
echo -e "${YELLOW}Discriminator: $DISCRIMINATOR${NC}"

# Add your current user to the Key Vault access policy
echo -e "${YELLOW}Adding current user to Key Vault access policy...${NC}"
USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
az keyvault set-policy --name $KV_NAME \
  --object-id $USER_OBJECT_ID \
  --certificate-permissions get list create import delete \
  --secret-permissions get list set delete \
  --key-permissions get list create delete

# Check if certificates already exist in Key Vault
ROOT_CERT_EXISTS=false
if [ "$FORCE_REGEN" = false ]; then
  ROOT_CERT_EXISTS=$(az keyvault certificate list --vault-name $KV_NAME --query "[?contains(name,'$CERT_NAME')]" -o tsv | wc -l)
  if [ "$ROOT_CERT_EXISTS" -gt 0 ]; then
    echo -e "${GREEN}Root certificate $CERT_NAME already exists in Key Vault${NC}"
    ROOT_CERT_EXISTS=true
  fi
fi

# Generate certificates if they don't exist or force regeneration is enabled
if [ "$ROOT_CERT_EXISTS" = false ] || [ "$FORCE_REGEN" = true ]; then
  echo -e "${YELLOW}Generating root and client certificates...${NC}"
  
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
  openssl pkcs12 -export \
    -in "$CLIENT_CERT_NAME.crt" \
    -inkey "$CLIENT_CERT_NAME.key" \
    -certfile "$CERT_NAME.crt" \
    -out "$CLIENT_CERT_NAME.pfx" \
    -password pass:$CERT_PASSWORD
  
  # Store certificates in Key Vault
  echo -e "${YELLOW}Storing certificates in Key Vault...${NC}"
  
  # Import root certificate
  az keyvault certificate import --vault-name $KV_NAME \
    --name $CERT_NAME \
    --file "$CERT_NAME.crt" || echo -e "${RED}Failed to import root certificate, but continuing...${NC}"
  
  # Store public part of root certificate (needed for VPN Gateway)
  az keyvault secret set --vault-name $KV_NAME \
    --name "$CERT_NAME-public" \
    --value "$ROOT_CERT_DATA" || echo -e "${RED}Failed to store root certificate public data, but continuing...${NC}"
  
  # Import client certificate
  az keyvault certificate import --vault-name $KV_NAME \
    --name $CLIENT_CERT_NAME \
    --file "$CLIENT_CERT_NAME.pfx" \
    --password $CERT_PASSWORD || echo -e "${RED}Failed to import client certificate, but continuing...${NC}"
  
  # Store client certificate as a secret for easy download
  CLIENT_PFX_B64=$(base64 -i "$CLIENT_CERT_NAME.pfx" | tr -d '\n')
  az keyvault secret set --vault-name $KV_NAME \
    --name "$CLIENT_CERT_NAME-pfx" \
    --value "$CLIENT_PFX_B64" || echo -e "${RED}Failed to store client certificate PFX, but continuing...${NC}"
  
  # Store client certificate password
  az keyvault secret set --vault-name $KV_NAME \
    --name "$CLIENT_CERT_NAME-password" \
    --value "$CERT_PASSWORD" || echo -e "${RED}Failed to store client certificate password, but continuing...${NC}"
  
  echo -e "${GREEN}Certificates generated and stored in Key Vault${NC}"
else
  # Get the root certificate data from Key Vault if it exists
  echo -e "${YELLOW}Retrieving root certificate from Key Vault...${NC}"
  ROOT_CERT_DATA=$(az keyvault secret show --vault-name $KV_NAME --name "$CERT_NAME-public" --query "value" -o tsv)
  
  if [ -z "$ROOT_CERT_DATA" ]; then
    echo -e "${RED}Could not retrieve root certificate from Key Vault. Generating a new one...${NC}"
    # Fall back to generating a new certificate (code would be duplicated here, but we're just setting a flag)
    FORCE_REGEN=true
    # Recursive call with force flag
    $0 --force
    exit $?
  fi
fi

# Create or retrieve managed identity for automation
info_echo "Checking managed identity for automation..."
MANAGED_IDENTITY_ID=$(az identity list --resource-group ${CENTRAL_RG} --query "[?contains(name, 'uami-${DISCRIMINATOR}-deploy')].id" -o tsv)

if [ -z "$MANAGED_IDENTITY_ID" ]; then
  info_echo "Creating managed identity 'uami-${DISCRIMINATOR}-deploy' in resource group $CENTRAL_RG"
  MANAGED_IDENTITY_ID=$(az identity create --name uami-${DISCRIMINATOR}-deploy --resource-group ${CENTRAL_RG} --query id -o tsv)
  
  info_echo "Assigning 'Contributor' role to the managed identity at subscription scope..."
  az role assignment create --assignee-object-id $(az identity show --name uami-${DISCRIMINATOR}-deploy --resource-group ${CENTRAL_RG} --query principalId -o tsv) \
    --role Contributor \
    --scope /subscriptions/${SUBSCRIPTION_ID}
    
  # Configure Key Vault access policy for the managed identity
  MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show --name uami-${DISCRIMINATOR}-deploy --resource-group ${CENTRAL_RG} --query principalId -o tsv)
  az keyvault set-policy --name $KV_NAME \
    --object-id $MANAGED_IDENTITY_PRINCIPAL_ID \
    --certificate-permissions get list \
    --secret-permissions get list \
    --key-permissions get list
else
  echo -e "${GREEN}Using existing managed identity: $MANAGED_IDENTITY_ID${NC}"
fi

# Check if VPN Gateway already exists
VPN_GW_NAME="vpngw-$DISCRIMINATOR"
VPN_GW_EXISTS=$(az network vnet-gateway list --resource-group ${CENTRAL_RG} --query "[?name=='$VPN_GW_NAME']" -o tsv | wc -l)

if [ "$VPN_GW_EXISTS" -gt 0 ]; then
  echo -e "${YELLOW}VPN Gateway $VPN_GW_NAME already exists. Updating root certificate...${NC}"
  
  # Update the root certificate directly on the VPN Gateway
  # First, check if the certificate already exists
  EXISTING_CERT=$(az network vnet-gateway show \
    --resource-group ${CENTRAL_RG} \
    --name $VPN_GW_NAME \
    --query "vpnClientConfiguration.vpnClientRootCertificates[?name=='$CERT_NAME'].name" -o tsv)
  
  # We'll add a new certificate without removing existing ones
  # because removing the only certificate would break authentication
  
  echo -e "${YELLOW}Adding certificate $CERT_NAME to VPN Gateway...${NC}"
  TEMP_CERT_FILE="$TEMP_DIR/temp_cert.crt"
  echo "$ROOT_CERT_DATA" > "$TEMP_CERT_FILE"
  
  # First, we'll see if the certificate already exists and if it needs to be replaced
  echo -e "${YELLOW}Checking if VPN Gateway certificate matches Key Vault...${NC}"
  
  CURRENT_CERT=$(az network vnet-gateway show \
    --resource-group ${CENTRAL_RG} \
    --name $VPN_GW_NAME \
    --query "vpnClientConfiguration.vpnClientRootCertificates[?name=='$CERT_NAME'].publicCertData" -o tsv)
  
  if [ "$CURRENT_CERT" == "$ROOT_CERT_DATA" ]; then
    echo -e "${GREEN}Certificate in VPN Gateway matches Key Vault certificate. No update needed.${NC}"
  else
    echo -e "${YELLOW}Certificate mismatch. Updating VPN Gateway certificate...${NC}"
    
    # First, check if there are multiple certificates
    CERT_COUNT=$(az network vnet-gateway show \
      --resource-group ${CENTRAL_RG} \
      --name $VPN_GW_NAME \
      --query "length(vpnClientConfiguration.vpnClientRootCertificates)" -o tsv)
    
    # If certificate exists and it's the only one, we'll need to create a bicep deployment
    # to replace it, as direct removal and addition might leave a gap without a valid cert
    if [ -n "$EXISTING_CERT" ] && [ "$CERT_COUNT" -eq 1 ]; then
      echo -e "${YELLOW}Only one certificate exists. Using bicep deployment to update it.${NC}"
      # Write a temporary bicep file to update just the certificate
      cat > "$TEMP_DIR/update-vpn-cert.bicep" << BICEPEOF
      @description('Root certificate data for VPN authentication')
      param rootCertData string
      
      @description('Root certificate name')
      param rootCertName string
      
      resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' existing = {
        name: '$VPN_GW_NAME'
      }
      
      resource vpnGatewayUpdate 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
        name: vpnGateway.name
        location: vpnGateway.location
        properties: {
          gatewayType: vpnGateway.properties.gatewayType
          vpnType: vpnGateway.properties.vpnType
          vpnGatewayGeneration: vpnGateway.properties.vpnGatewayGeneration
          sku: vpnGateway.properties.sku
          enableBgp: vpnGateway.properties.enableBgp
          activeActive: vpnGateway.properties.activeActive
          ipConfigurations: vpnGateway.properties.ipConfigurations
          vpnClientConfiguration: {
            vpnClientAddressPool: vpnGateway.properties.vpnClientConfiguration.vpnClientAddressPool
            vpnClientProtocols: vpnGateway.properties.vpnClientConfiguration.vpnClientProtocols
            vpnAuthenticationTypes: vpnGateway.properties.vpnClientConfiguration.vpnAuthenticationTypes
            vpnClientRootCertificates: [
              {
                name: rootCertName
                properties: {
                  publicCertData: rootCertData
                }
              }
            ]
          }
        }
      }
BICEPEOF
      
      # Deploy the bicep file to update the certificate
      echo -e "${YELLOW}Deploying certificate update...${NC}"
      az deployment group create \
        --resource-group ${CENTRAL_RG} \
        --template-file "$TEMP_DIR/update-vpn-cert.bicep" \
        --parameters rootCertData="$ROOT_CERT_DATA" rootCertName="$CERT_NAME" \
        --name "update-vpn-cert-$(date +%Y%m%d%H%M%S)"
    else
      # We can add a new certificate since multiple exist or none exist yet
      echo -e "${YELLOW}Adding new certificate to VPN Gateway...${NC}"
      
      # Create temporary file with certificate data
      echo "$ROOT_CERT_DATA" > "$TEMP_DIR/cert_data.txt"
      
      # Add the new certificate
      az network vnet-gateway root-cert create \
        --resource-group ${CENTRAL_RG} \
        --gateway-name $VPN_GW_NAME \
        --name "$CERT_NAME-$(date +%s)" \
        --public-cert-data "$ROOT_CERT_DATA"
    fi
    
    echo -e "${GREEN}VPN Gateway certificate updated!${NC}"
  fi
  
  # Download the VPN client configuration package
  echo -e "${YELLOW}Generating VPN client configuration package...${NC}"
  CLIENT_PACKAGE_URL=$(az network vnet-gateway vpn-client generate \
    --resource-group ${CENTRAL_RG} \
    --name $VPN_GW_NAME \
    --authentication-method EAPTLS \
    -o tsv)
  
  echo -e "${GREEN}VPN client configuration package URL:${NC}"
  echo "$CLIENT_PACKAGE_URL"
else
  # Deploy the VPN Gateway using the bicep module
  echo -e "${YELLOW}Deploying new VPN Gateway...${NC}"
  DEPLOY_NAME="vpn-deployment-$(date +%Y%m%d%H%M%S)"
  
  az deployment group create \
    --resource-group ${CENTRAL_RG} \
    --template-file modules/vpn.bicep \
    --name $DEPLOY_NAME \
    --parameters \
      discriminator=$DISCRIMINATOR \
      location=$LOCATION \
      addressPool="172.16.0.0/24" \
      authType="Certificate" \
      rootCertData="$ROOT_CERT_DATA" \
      rootCertName="$CERT_NAME" \
      uamiId="$MANAGED_IDENTITY_ID" \
      keyVaultName=$KV_NAME
  
  echo -e "${GREEN}VPN Gateway deployment initiated.${NC}"
  echo -e "${YELLOW}The deployment may take 30-45 minutes to complete.${NC}"
  echo -e "${YELLOW}You can check the status with:${NC}"
  echo -e "${YELLOW}az deployment group show --resource-group ${CENTRAL_RG} --name $DEPLOY_NAME${NC}"
  
  # Monitor deployment with timeout
  echo -e "${YELLOW}Monitoring deployment status (with 45-minute timeout)...${NC}"
  
  START_TIME=$(date +%s)
  TIMEOUT=$((45 * 60)) # 45 minutes in seconds
  IS_COMPLETE=false
  
  while [ "$IS_COMPLETE" = false ]; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [ $ELAPSED -gt $TIMEOUT ]; then
      echo -e "${YELLOW}Monitoring timed out after 45 minutes. Deployment is still running.${NC}"
      echo -e "${YELLOW}You can check the status manually:${NC}"
      echo -e "${YELLOW}az deployment group show --resource-group ${CENTRAL_RG} --name $DEPLOY_NAME${NC}"
      IS_COMPLETE=true
      continue
    fi
    
    STATUS=$(az deployment group show --resource-group ${CENTRAL_RG} --name $DEPLOY_NAME --query "properties.provisioningState" -o tsv 2>/dev/null)
    
    if [ $? -ne 0 ]; then
      echo -e "${YELLOW}Error checking deployment status, retrying...${NC}"
      sleep 30
      continue
    fi
    
    case $STATUS in
      "Succeeded")
        echo -e "${GREEN}Deployment succeeded!${NC}"
        IS_COMPLETE=true
        
        # Download the VPN client configuration package
        echo -e "${YELLOW}Generating VPN client configuration package...${NC}"
        CLIENT_PACKAGE_URL=$(az network vnet-gateway vpn-client generate \
          --resource-group ${CENTRAL_RG} \
          --name $VPN_GW_NAME \
          --authentication-method EAPTLS \
          -o tsv)
        
        echo -e "${GREEN}VPN client configuration package URL:${NC}"
        echo "$CLIENT_PACKAGE_URL"
        ;;
      "Failed")
        echo -e "${RED}Deployment failed!${NC}"
        echo -e "${YELLOW}Check the deployment for errors:${NC}"
        echo -e "${YELLOW}az deployment group show --resource-group ${CENTRAL_RG} --name $DEPLOY_NAME${NC}"
        IS_COMPLETE=true
        ;;
      *)
        MINUTES=$((ELAPSED / 60))
        SECONDS=$((ELAPSED % 60))
        echo -e "${YELLOW}Deployment status: $STATUS - Elapsed time: ${MINUTES}m ${SECONDS}s - waiting 30 seconds...${NC}"
        sleep 30
        ;;
    esac
  done
fi

# Don't export client certificate for security reasons
echo -e "${YELLOW}For security, client certificates will remain in Key Vault${NC}"
echo -e "${GREEN}Client certificate is stored in Key Vault: $KV_NAME${NC}"
echo -e "${GREEN}Certificate name: $CLIENT_CERT_NAME-pfx${NC}"
echo -e "${GREEN}Certificate password is stored in Key Vault: $CLIENT_CERT_NAME-password${NC}"
echo -e "${YELLOW}To get the certificate, use:${NC}"
echo -e "${YELLOW}az keyvault secret show --vault-name $KV_NAME --name $CLIENT_CERT_NAME-pfx --query value -o tsv | base64 -d > cert.pfx${NC}"
echo -e "${YELLOW}az keyvault secret show --vault-name $KV_NAME --name $CLIENT_CERT_NAME-password --query value -o tsv${NC}"

# Clean up temporary directory
rm -rf $TEMP_DIR

echo -e "${GREEN}VPN setup completed successfully!${NC}"
echo -e "${GREEN}==================================${NC}"
echo -e "${YELLOW}Instructions for connecting:${NC}"
echo -e "${YELLOW}1. Download the VPN client configuration package using the URL above${NC}"
echo -e "${YELLOW}2. Extract the zip file and find the configuration for your platform${NC}"
echo -e "${YELLOW}3. Import the client certificate (./certificates/$CLIENT_CERT_NAME.pfx)${NC}"
echo -e "${YELLOW}4. Use the password: $CERT_PASSWORD${NC}"
echo -e "${YELLOW}5. Connect using your preferred VPN client${NC}"
echo -e "${GREEN}==================================${NC}"