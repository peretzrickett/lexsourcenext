#!/bin/bash

# Define Variables
SUBSCRIPTION_ID="ed42d05a-0eb7-4618-b08d-495f9f21ab85"
PRIVATE_ENDPOINT_ID="/subscriptions/ed42d05a-0eb7-4618-b08d-495f9f21ab85/resourceGroups/rg-ClientA/providers/Microsoft.Network/privateEndpoints/pe-app-lexsb-ClientA"

# Echo variables for debugging
echo "Subscription ID: $SUBSCRIPTION_ID"
echo "Private Endpoint ID: $PRIVATE_ENDPOINT_ID"
echo "Cloud: $(az cloud show --query name -o tsv)"

# Check if subscription ID is empty
if [ -z "$SUBSCRIPTION_ID" ]; then
    echo "Error: Subscription ID is empty or not set"
    exit 1
fi

# Ensure we're in AzureCloud
current_cloud=$(az cloud show --query name -o tsv)
if [ "$current_cloud" != "AzureCloud" ]; then
    echo "Switching to AzureCloud..."
    az cloud set --name AzureCloud || {
        echo "Error: Failed to switch to AzureCloud"
        exit 1
    }
fi

# Set the Azure CLI context to the specified subscription
az account set --subscription "$SUBSCRIPTION_ID" || {
    echo "Error: Failed to set subscription context for $SUBSCRIPTION_ID"
    exit 1
}

# Verify the subscription is set correctly
current_subscription=$(az account show --query id -o tsv)
if [ "$current_subscription" != "$SUBSCRIPTION_ID" ]; then
    echo "Error: Current subscription ($current_subscription) does not match expected ($SUBSCRIPTION_ID)"
    exit 1
fi

# Retrieve Private Endpoint details for debugging
echo "Private Endpoint Details:"
az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces" -o json

# Retrieve Private IP from Private Endpoint with fallback
PRIVATE_IP=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[0].ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null)

# Enhanced error handling
if [ -z "$PRIVATE_IP" ]; then
    echo "Error: Private IP not found for Private Endpoint $PRIVATE_ENDPOINT_ID"
    echo "Checking NIC and IP configurations..."
    NIC_ID=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[0].id" -o tsv 2>/dev/null)
    if [ -n "$NIC_ID" ]; then
        echo "NIC ID: $NIC_ID"
        NIC_IP=$(az network nic show --ids "$NIC_ID" --query "ipConfigurations[0].privateIPAddress" -o tsv 2>/dev/null)
        if [ -n "$NIC_IP" ]; then
            echo "Found Private IP via NIC: $NIC_IP"
            PRIVATE_IP="$NIC_IP"
        else
            echo "No IP configuration found in NIC"
            az network nic show --ids "$NIC_ID" --query "ipConfigurations" -o json
        fi
    else
        echo "No NIC found for Private Endpoint"
    fi
    exit 1
fi

# Output Private IP to both console and output path for reliability
echo "Private IP: $PRIVATE_IP"
echo "$PRIVATE_IP" > $AZ_SCRIPTS_OUTPUT_PATH
echo "::set-output name=privateIp::$PRIVATE_IP" # GitHub Actions-style output for compatibility