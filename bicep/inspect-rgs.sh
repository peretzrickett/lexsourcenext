#!/bin/bash

# Array of resource groups to check
RESOURCE_GROUPS=("rg-central" "rg-clienta" "rg-clientb")

# Function to inspect and display deployments and dependencies in a resource group
inspect_resource_group() {
    local RG=$1
    echo "Inspecting deployments and dependencies in resource group: $RG"

    # 1. List all deployments
    echo "Listing deployments in $RG..."
    az deployment group list --resource-group "$RG" --query "[].{Name:name, Timestamp:properties.timestamp, State:properties.provisioningState}" -o table

    # 2. List deployment scripts
    echo "Listing deployment scripts in $RG..."
    az resource list --resource-group "$RG" --resource-type Microsoft.Resources/deploymentScripts --query "[].{Name:name, ProvisioningState:properties.provisioningState, Location:location}" -o table

    # 3. List Container Instances (used by deployment scripts)
    echo "Listing Container Instances in $RG..."
    az container list --resource-group "$RG" --query "[].{Name:name, State:provisioningState, IP:ipAddress.ip}" -o table

    # 4. List Storage Accounts (used by deployment scripts for logs)
    echo "Listing Storage Accounts in $RG..."
    az storage account list --resource-group "$RG" --query "[].{Name:name, Location:location, SKU:sku.name}" -o table

    # 5. Check for dependent Private Endpoints or VNets (if relevant)
    echo "Listing Private Endpoints in $RG..."
    az network private-endpoint list --resource-group "$RG" --query "[].{Name:name, State:provisioningState, VNet:networkInterfaces[0].properties.virtualNetwork.id}" -o table

    echo "Listing Virtual Networks in $RG..."
    az network vnet list --resource-group "$RG" --query "[].{Name:name, AddressSpace:addressSpace.addressPrefixes}" -o table

    echo "Inspection of $RG completed."
}

# Process each resource group sequentially (can be parallelized, but sequential for clarity)
for RG in "${RESOURCE_GROUPS[@]}"; do
    inspect_resource_group "$RG"
    sleep 2  # Brief pause to avoid rate limiting
done

echo "Inspection of all resource groups completed."