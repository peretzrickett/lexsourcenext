#!/bin/bash
# Script to deploy VPN Gateway with certificate-based authentication

set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CERT_DIR="./certificates"
CERT_NAME="P2SRootCert"
LOCATION="eastus"
DISCRIMINATOR="lexsb"

# Function to display usage
function display_usage {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --cert-name    Certificate name (default: P2SRootCert)"
  echo "  -d, --cert-dir     Certificate directory (default: ./certificates)"
  echo "  -l, --location     Azure region (default: eastus)"
  echo "  -p, --prefix       Resource name discriminator (default: lexsb)"
  echo "  -h, --help         Display this help message"
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
    -d|--cert-dir)
      CERT_DIR="$2"
      shift 2
      ;;
    -l|--location)
      LOCATION="$2"
      shift 2
      ;;
    -p|--prefix)
      DISCRIMINATOR="$2"
      shift 2
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

# Check if certificate exists
CERT_PATH="$CERT_DIR/$CERT_NAME.cer"
if [ ! -f "$CERT_PATH" ]; then
  echo -e "${RED}Error: Certificate not found at $CERT_PATH${NC}"
  echo -e "${YELLOW}Generate a certificate first using generate-vpn-cert.sh${NC}"
  exit 1
fi

# Read certificate data
CERT_DATA=$(cat "$CERT_PATH")
if [ -z "$CERT_DATA" ]; then
  echo -e "${RED}Error: Failed to read certificate data${NC}"
  exit 1
fi

echo -e "${YELLOW}Deploying VPN Gateway with certificate-based authentication...${NC}"
echo -e "${YELLOW}Certificate: $CERT_PATH${NC}"
echo -e "${YELLOW}Location: $LOCATION${NC}"
echo -e "${YELLOW}Discriminator: $DISCRIMINATOR${NC}"

# Deploy the VPN Gateway using the bicep module directly
echo -e "${YELLOW}Creating VPN Gateway resources...${NC}"
az deployment group create \
  --resource-group rg-central \
  --template-file modules/vpn.bicep \
  --parameters \
    discriminator=$DISCRIMINATOR \
    location=$LOCATION \
    addressPool="172.16.0.0/24" \
    authType="Certificate" \
    rootCertData="$CERT_DATA" \
    rootCertName="$CERT_NAME" \
  --no-wait

echo -e "${GREEN}VPN Gateway deployment initiated.${NC}"
echo -e "${YELLOW}The deployment will take approximately 30-45 minutes to complete.${NC}"
echo -e "${YELLOW}You can check the status with:${NC}"
echo -e "${YELLOW}az deployment group show --resource-group rg-central --name vpn${NC}"

echo -e "${GREEN}After deployment completes:${NC}"
echo -e "${YELLOW}1. Download the VPN client configuration package from Azure Portal${NC}"
echo -e "${YELLOW}2. Install the VPN client on your device${NC}"
echo -e "${YELLOW}3. Import the client certificate ($CERT_DIR/P2SClientCert.pfx)${NC}"
echo -e "${YELLOW}4. Connect to the VPN to access resources securely${NC}"