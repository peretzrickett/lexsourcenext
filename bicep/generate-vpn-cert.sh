#!/bin/bash
# Script to generate a self-signed root certificate for Azure VPN

set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default values
CERT_NAME="P2SRootCert"
CERT_PASSWORD="Password1!"  # Change this in production
CLIENT_CERT_NAME="P2SClientCert"
OUTPUT_DIR="./certificates"

# Function to display usage
function display_usage {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -n, --name        Certificate name (default: P2SRootCert)"
  echo "  -p, --password    Certificate password (default: Password1!)"
  echo "  -c, --client      Client certificate name (default: P2SClientCert)"
  echo "  -o, --output      Output directory (default: ./certificates)"
  echo "  -h, --help        Display this help message"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -n|--name)
      CERT_NAME="$2"
      shift 2
      ;;
    -p|--password)
      CERT_PASSWORD="$2"
      shift 2
      ;;
    -c|--client)
      CLIENT_CERT_NAME="$2"
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR="$2"
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

# Check if OpenSSL is installed
if ! command -v openssl &> /dev/null; then
  echo -e "${RED}Error: OpenSSL is not installed. Please install it first.${NC}"
  exit 1
fi

# Create output directory if it doesn't exist
mkdir -p $OUTPUT_DIR

echo -e "${YELLOW}Generating root certificate...${NC}"

# Generate a root certificate
openssl req -x509 -new -nodes -sha256 -days 3650 \
  -subj "/CN=$CERT_NAME" \
  -keyout "$OUTPUT_DIR/$CERT_NAME.key" \
  -out "$OUTPUT_DIR/$CERT_NAME.crt"

# Convert to base64 format for Azure
openssl x509 -in "$OUTPUT_DIR/$CERT_NAME.crt" -outform der | base64 > "$OUTPUT_DIR/$CERT_NAME.cer"

# Display the certificate data for Azure VPN configuration
echo -e "${GREEN}Root certificate generated successfully.${NC}"
echo -e "${YELLOW}Certificate name: $CERT_NAME${NC}"
echo -e "${YELLOW}Certificate path: $OUTPUT_DIR/$CERT_NAME.crt${NC}"
echo -e "${YELLOW}Base64 encoded certificate for Azure:${NC}"
cat "$OUTPUT_DIR/$CERT_NAME.cer"
echo ""

# Generate client certificate
echo -e "${YELLOW}Generating client certificate...${NC}"

# Generate client key
openssl genrsa -out "$OUTPUT_DIR/$CLIENT_CERT_NAME.key" 2048

# Generate client certificate request
openssl req -new \
  -subj "/CN=$CLIENT_CERT_NAME" \
  -key "$OUTPUT_DIR/$CLIENT_CERT_NAME.key" \
  -out "$OUTPUT_DIR/$CLIENT_CERT_NAME.csr"

# Sign the client certificate with the root certificate
openssl x509 -req -in "$OUTPUT_DIR/$CLIENT_CERT_NAME.csr" \
  -CA "$OUTPUT_DIR/$CERT_NAME.crt" \
  -CAkey "$OUTPUT_DIR/$CERT_NAME.key" \
  -CAcreateserial \
  -out "$OUTPUT_DIR/$CLIENT_CERT_NAME.crt" \
  -days 365 \
  -sha256

# Export client certificate as pfx for client import
openssl pkcs12 -export \
  -in "$OUTPUT_DIR/$CLIENT_CERT_NAME.crt" \
  -inkey "$OUTPUT_DIR/$CLIENT_CERT_NAME.key" \
  -certfile "$OUTPUT_DIR/$CERT_NAME.crt" \
  -out "$OUTPUT_DIR/$CLIENT_CERT_NAME.pfx" \
  -password pass:$CERT_PASSWORD

echo -e "${GREEN}Client certificate generated successfully.${NC}"
echo -e "${YELLOW}Client certificate: $OUTPUT_DIR/$CLIENT_CERT_NAME.pfx${NC}"
echo -e "${YELLOW}Password: $CERT_PASSWORD${NC}"
echo -e "${GREEN}Use this client certificate for VPN connections.${NC}"
echo ""

# Create instructions for deployment
echo -e "${GREEN}To deploy VPN Gateway with this certificate:${NC}"
echo -e "${YELLOW}1. Add the root certificate to Azure VPN Gateway configuration${NC}"
echo -e "${YELLOW}2. Use the following parameter for bicep deployment:${NC}"
echo -e "${YELLOW}   rootCertData: '$(cat $OUTPUT_DIR/$CERT_NAME.cer)'${NC}"
echo ""
echo -e "${GREEN}To connect to the VPN:${NC}"
echo -e "${YELLOW}1. Download the VPN client configuration from Azure Portal${NC}"
echo -e "${YELLOW}2. Import the client certificate ($CLIENT_CERT_NAME.pfx) to your device${NC}"
echo -e "${YELLOW}3. Use the password: $CERT_PASSWORD${NC}"