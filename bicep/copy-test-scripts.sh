#!/bin/bash
# Script to copy test scripts and deployment files to the VM
# Run this from the deployment machine

# Get Firewall IP address
FW_IP=$(az network public-ip show --resource-group rg-central --name ip-globalFirewall --query ipAddress -o tsv)

if [ -z "$FW_IP" ]; then
  echo "Error: Could not get Firewall IP address"
  exit 1
fi

echo "Firewall IP address: $FW_IP"
echo "Copying scripts and deployment files to VM..."

# Make scripts executable
chmod +x test-private-dns.sh test-connectivity.sh deploy-app.sh

# Copy scripts, app files, and configuration to VM
scp -i ~/.ssh/vm-network-tester_key.pem \
  test-private-dns.sh \
  test-connectivity.sh \
  deploy-app.sh \
  clients.json \
  lexdemo_202412261902.zip \
  lexdemodb_2024_12_03-04-53.bacpac \
  azureuser@$FW_IP:~/

echo "Files copied successfully."
echo ""
echo "To run on the VM:"
echo "  1. SSH to VM: ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@$FW_IP"
echo "  2. Run DNS tests: ./test-private-dns.sh"
echo "  3. Run connectivity tests: ./test-connectivity.sh"
echo "  4. Deploy web app and database: ./deploy-app.sh"
echo ""
echo "Note: The deploy-app.sh script will deploy the web app and database directly through private endpoints."