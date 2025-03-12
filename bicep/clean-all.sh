#!/bin/bash
set -euo pipefail

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Central resource group
RESOURCE_GROUP="rg-${DISCRIMINATOR}-central"

echo "=== Starting full cleanup of stuck resources in $RESOURCE_GROUP ==="
echo "This script will perform a comprehensive cleanup of stuck resources:"
echo "1. Delete running or failed deployments"
echo "2. Delete deployment scripts"
echo "3. Delete storage accounts linked to deployment scripts"
echo "4. Delete container instances"
echo ""
echo "Resource Group: $RESOURCE_GROUP"

# Check if resource group exists
echo "Checking if resource group exists..."
RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP")

if [ "$RG_EXISTS" = "false" ]; then
    echo "Resource group $RESOURCE_GROUP does not exist. Nothing to clean up."
    exit 0
fi

# Function to catch errors but continue
function run_with_retry {
    local max_attempts=3
    local attempt=1
    local sleep_time=5
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        else
            echo "Command failed (attempt $attempt/$max_attempts), retrying in ${sleep_time}s..."
            sleep $sleep_time
            attempt=$((attempt + 1))
        fi
    done
    
    echo "Command failed after $max_attempts attempts: $@"
    return 1
}

# 1. Get and delete all deployments
echo "Looking for active or failed deployments..."
DEPLOYMENTS=$(az deployment group list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)

if [ -n "$DEPLOYMENTS" ]; then
    echo "Found deployments to clean up:"
    echo "$DEPLOYMENTS"
    
    for DEPLOYMENT in $DEPLOYMENTS; do
        echo "Deleting deployment: $DEPLOYMENT"
        run_with_retry az deployment group delete --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT" || true
    done
else
    echo "No deployments found."
fi

# 2. Find and delete deployment scripts
echo "Looking for deployment scripts..."
DEPLOYMENT_SCRIPTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Resources/deploymentScripts" --query "[].id" -o tsv)

if [ -n "$DEPLOYMENT_SCRIPTS" ]; then
    echo "Found deployment scripts to clean up:"
    echo "$DEPLOYMENT_SCRIPTS"
    
    for SCRIPT_ID in $DEPLOYMENT_SCRIPTS; do
        echo "Deleting deployment script: $SCRIPT_ID"
        run_with_retry az resource delete --ids "$SCRIPT_ID" || true
    done
else
    echo "No deployment scripts found."
fi

# 3. Find and delete storage accounts
echo "Looking for storage accounts..."
STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)

if [ -n "$STORAGE_ACCOUNTS" ]; then
    echo "Found storage accounts to clean up:"
    echo "$STORAGE_ACCOUNTS"
    
    for STORAGE_ACCOUNT in $STORAGE_ACCOUNTS; do
        echo "Deleting storage account: $STORAGE_ACCOUNT"
        run_with_retry az storage account delete --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --yes || true
    done
else
    echo "No storage accounts found."
fi

# 4. Find and delete container instances
echo "Looking for container instances..."
CONTAINER_GROUPS=$(az container list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)

if [ -n "$CONTAINER_GROUPS" ]; then
    echo "Found container instances to clean up:"
    echo "$CONTAINER_GROUPS"
    
    for CONTAINER_GROUP in $CONTAINER_GROUPS; do
        echo "Deleting container group: $CONTAINER_GROUP"
        run_with_retry az container delete --name "$CONTAINER_GROUP" --resource-group "$RESOURCE_GROUP" --yes || true
    done
else
    echo "No container instances found."
fi

# 5. Verify cleanup success
echo "Verifying cleanup..."

# Check for remaining deployment scripts
REMAINING_SCRIPTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type "Microsoft.Resources/deploymentScripts" --query "length(@)" -o tsv)
if [ "$REMAINING_SCRIPTS" -eq "0" ]; then
    echo "✅ All deployment scripts removed successfully."
else
    echo "⚠️ $REMAINING_SCRIPTS deployment scripts still remain. Manual cleanup may be required."
fi

# Check for remaining container instances
REMAINING_CONTAINERS=$(az container list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
if [ "$REMAINING_CONTAINERS" -eq "0" ]; then
    echo "✅ All container instances removed successfully."
else
    echo "⚠️ $REMAINING_CONTAINERS container instances still remain. Manual cleanup may be required."
fi

# Check for remaining deployments
REMAINING_DEPLOYMENTS=$(az deployment group list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
if [ "$REMAINING_DEPLOYMENTS" -eq "0" ]; then
    echo "✅ All deployments removed successfully."
else
    echo "⚠️ $REMAINING_DEPLOYMENTS deployments still remain. Manual cleanup may be required."
fi

echo "=== Cleanup process completed ==="