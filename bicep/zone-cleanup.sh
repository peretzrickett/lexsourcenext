#!/bin/bash

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Array of resource groups with discriminator
RESOURCE_GROUPS=(rg-${DISCRIMINATOR}-central rg-${DISCRIMINATOR}-clienta rg-${DISCRIMINATOR}-clientb)

# List of DNS zones to clean up
DNS_ZONES=(
  "privatelink.azurewebsites.net"
  "privatelink.database.windows.net"
  "privatelink.monitor.azure.com"
  "privatelink.vaultcore.azure.net"
  "privatelink.blob.core.windows.net"
  "privatelink.file.core.windows.net"
  "privatelink.insights.azure.com"
  "privatelink.core.windows.net"
)

# Maximum concurrent processes per resource group
MAX_CONCURRENT=2  # Reduced to avoid Azure API rate limiting

# Maximum retries for failed Azure CLI commands
MAX_RETRIES=3
RETRY_DELAY=5  # Seconds to wait between retries

# Function to check if the script has sufficient permissions
check_permissions() {
    local RG=$1
    echo "Checking permissions for resource group $RG..."
    az group show --name "$RG" --query "properties.provisioningState" -o tsv 2>/dev/null || {
        echo "Error: Insufficient permissions to access resource group $RG. Ensure uami-deployment-scripts or user has Contributor/Owner role."
        exit 1
    }
}

# Function to execute Azure CLI command with retries
run_az_command() {
    local cmd="$1"
    local retries=$MAX_RETRIES
    while [ $retries -gt 0 ]; do
        if $cmd; then
            return 0
        fi
        echo "Command failed, retrying ($retries attempts left)..."
        sleep $RETRY_DELAY
        ((retries--))
    done
    echo "Error: Command failed after $MAX_RETRIES retries: $cmd"
    return 1
}

# Function to delete DNS records in a zone
delete_dns_records() {
  local RESOURCE_GROUP=$1
  local DNS_ZONE=$2
  
  echo "Checking for DNS zone: $DNS_ZONE in $RESOURCE_GROUP"
  
  # Check if zone exists
  if ! az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$DNS_ZONE" --query "name" -o tsv &>/dev/null; then
    echo "  Zone not found, skipping."
    return 0
  fi
  
  echo "  Zone found, processing..."
  
  # Get all A records
  local A_RECORDS=$(az network private-dns record-set a list \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --query "[].name" -o tsv 2>/dev/null)
  
  if [ -n "$A_RECORDS" ]; then
    echo "  Found $(echo "$A_RECORDS" | wc -l | tr -d ' ') A records"
    for RECORD in $A_RECORDS; do
      echo "  Deleting A record: $RECORD"
      az network private-dns record-set a delete \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE" \
        --name "$RECORD" \
        --yes \
        --output none \
        || echo "    Failed to delete A record: $RECORD"
    done
  else
    echo "  No A records found"
  fi
  
  # Get all virtual network links
  local VNET_LINKS=$(az network private-dns link vnet list \
    --resource-group "$RESOURCE_GROUP" \
    --zone-name "$DNS_ZONE" \
    --query "[].name" -o tsv 2>/dev/null)
  
  if [ -n "$VNET_LINKS" ]; then
    echo "  Found $(echo "$VNET_LINKS" | wc -l | tr -d ' ') VNet links"
    for LINK in $VNET_LINKS; do
      echo "  Deleting VNet link: $LINK"
      az network private-dns link vnet delete \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$DNS_ZONE" \
        --name "$LINK" \
        --yes \
        --output none \
        || echo "    Failed to delete VNet link: $LINK"
    done
  else
    echo "  No VNet links found"
  fi
  
  # Delete the zone itself
  echo "  Deleting DNS zone: $DNS_ZONE"
  az network private-dns zone delete \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DNS_ZONE" \
    --yes \
    --output none \
    || echo "    Failed to delete DNS zone: $DNS_ZONE"
}

# Main processing
echo "Starting DNS zone cleanup..."

# Process the central resource group first
CENTRAL_RG="${RESOURCE_GROUPS[0]}"
echo "Processing central resource group: $CENTRAL_RG"

for ZONE in "${DNS_ZONES[@]}"; do
  delete_dns_records "$CENTRAL_RG" "$ZONE"
done

echo "Cleanup completed."