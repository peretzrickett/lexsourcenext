# Define Variables
SUBSCRIPTION_ID="ed42d05a-0eb7-4618-b08d-495f9f21ab85"
PE_NAME="pe-app-lexsb-ClientA"
RG_NAME="rg-ClientA"

# Get NIC Name
NIC_NAME=$(az network private-endpoint show --name $PE_NAME --resource-group $RG_NAME --query "networkInterfaces[0].id" --output tsv | awk -F'/' '{print $NF}')

# Get IP Configuration Name
IPCONFIG_NAME=$(az network nic show --name $NIC_NAME --resource-group $RG_NAME --query "ipConfigurations[0].name" --output tsv)

# Construct Full Resource ID
IPCONFIG_ID="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME/providers/Microsoft.Network/networkInterfaces/$NIC_NAME/ipConfigurations/$IPCONFIG_NAME"

# Extract Private IP Address from IP Configuration
PRIVATE_IP=$(az resource show --ids "$IPCONFIG_ID" --query "properties.privateIPAddress" --output tsv)

# Output Results
echo "NIC Name: $NIC_NAME"
echo "IP Configuration: $IPCONFIG_NAME"
echo "Private IP: $PRIVATE_IP"
