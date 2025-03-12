#!/bin/bash

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Array of resource groups to inspect with discriminator
RESOURCE_GROUPS=("rg-${DISCRIMINATOR}-central" "rg-${DISCRIMINATOR}-clienta" "rg-${DISCRIMINATOR}-clientb")

# Function to list all resources in a specific resource group
list_resource_group() {
    local rg=$1
    echo "====== Resources in $rg ======"
    
    # Get all resources in the resource group
    echo "Fetching resources..."
    RESOURCES=$(az resource list --resource-group "$rg" --query "[].{Name:name, Type:type}" -o tsv)
    
    if [ -z "$RESOURCES" ]; then
        echo "No resources found in $rg."
        return
    fi
    
    # Display resources in a readable format
    echo "$RESOURCES" | while read -r line; do
        NAME=$(echo "$line" | cut -f1)
        TYPE=$(echo "$line" | cut -f2)
        echo "[$TYPE] $NAME"
    done
    
    echo ""
}

# Process each resource group
for rg in "${RESOURCE_GROUPS[@]}"; do
    list_resource_group "$rg"
done

echo "Resource inspection complete."