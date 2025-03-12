#!/bin/bash

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Reset Azure cloud resources while preserving specific resources
# Preserves:
# - Key Vaults
# - Storage Accounts
# - Managed Identities
# - vm-network-tester VM and related assets
# - vnet-${DISCRIMINATOR}-central

echo "===== RESET CLOUD OPERATION ====="
echo "WARNING: This will delete most resources in the current subscription!"
echo "The following resource types will be preserved:"
echo "- Key Vaults (Microsoft.KeyVault/vaults)"
echo "- Storage Accounts (Microsoft.Storage/storageAccounts)"
echo "- Managed Identities (Microsoft.ManagedIdentity/userAssignedIdentities)"
echo "- vm-network-tester VM and related assets"
echo "- vnet-${DISCRIMINATOR}-central"
echo ""

# Prompt for confirmation
read -p "Are you sure you want to proceed? This operation cannot be undone. (type 'YES' to confirm): " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Operation cancelled by user."
    exit 0
fi

# Verify subscription
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Target subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
read -p "Is this the correct subscription? (type 'YES' to confirm): " CONFIRM_SUB
if [ "$CONFIRM_SUB" != "YES" ]; then
    echo "Operation cancelled. Please select the correct subscription using 'az account set'."
    exit 0
fi

# Cancel all active deployments first
echo "Cancelling all active deployments..."
./cancel-all-deployments.sh

# Function to get all resource IDs except specified types and names
get_resources_to_delete() {
    az resource list --query "[?type!='Microsoft.KeyVault/vaults' && type!='Microsoft.Storage/storageAccounts' && type!='Microsoft.ManagedIdentity/userAssignedIdentities' && !(name=='vnet-${DISCRIMINATOR}-central' || contains(name, 'vm-network-tester'))].[id]" -o tsv
}

# Function to delete resources from a specified file
delete_resources_from_file() {
    local file=$1
    local total=$(wc -l < "$file")
    local count=0
    
    echo "Starting deletion of $total resources..."
    
    while IFS= read -r resource_id; do
        count=$((count + 1))
        echo "[$count/$total] Deleting: $resource_id"
        
        # Extract resource group from resource ID
        resource_group=$(echo "$resource_id" | cut -d'/' -f5)
        
        # Skip if it contains any protected names (additional safety)
        if [[ "$resource_id" == *"KeyVault"* || 
              "$resource_id" == *"storageAccount"* || 
              "$resource_id" == *"ManagedIdentity"* || 
              "$resource_id" == *"network-tester"* || 
              "$resource_id" == *"vnet-${DISCRIMINATOR}-central"* ]]; then
            echo "Skipping protected resource: $resource_id"
            continue
        fi
        
        # Delete the resource
        az resource delete --ids "$resource_id" --verbose || {
            echo "Warning: Failed to delete $resource_id. It might have dependencies or special deletion requirements."
        }
        
        # Brief pause to prevent rate limiting
        sleep 1
    done < "$file"
}

# Generate the list of resources to delete
echo "Identifying resources to delete..."
get_resources_to_delete > resources_to_delete.txt

# Display count and ask for final confirmation
RESOURCE_COUNT=$(wc -l < resources_to_delete.txt)
echo "Found $RESOURCE_COUNT resources to delete."
echo "Resource list saved to resources_to_delete.txt"

read -p "Begin deletion process? (type 'PROCEED' to start): " START_DELETION
if [ "$START_DELETION" != "PROCEED" ]; then
    echo "Deletion cancelled by user."
    echo "You can review the resources in 'resources_to_delete.txt'"
    exit 0
fi

# Perform the deletion
delete_resources_from_file "resources_to_delete.txt"

echo "Resource deletion completed."
echo "NOTE: Some resources may still exist due to dependencies or protection."
echo "To complete cleanup, you may need to manually delete resource groups."

# Clean up the temporary file
rm -f resources_to_delete.txt

echo "Reset cloud operation completed successfully."