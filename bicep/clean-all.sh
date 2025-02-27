#!/bin/bash

RESOURCE_GROUP="rg-central"

echo "Starting comprehensive cleanup of stuck resources in $RESOURCE_GROUP..."

# 1. Delete Running/Failed Deployments
DEPLOYMENTS=$(az deployment group list --resource-group "$RESOURCE_GROUP" --query "[?properties.provisioningState=='Running' || properties.provisioningState=='Failed'].name" -o tsv 2>/dev/null)
if [ -n "$DEPLOYMENTS" ]; then
    echo "Deleting stuck deployments..."
    for DEPLOYMENT in $DEPLOYMENTS; do
        echo "Deleting deployment: $DEPLOYMENT"
        az deployment group delete --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT"  || {
            echo "Warning: Failed to delete $DEPLOYMENT. Trying force delete..."
            az resource delete --resource-group "$RESOURCE_GROUP" --name "$DEPLOYMENT" --resource-type Microsoft.Resources/deployments --force  2>/dev/null || {
                echo "Error: Could not delete $DEPLOYMENT. Check permissions or open a support ticket."
            }
        }
        sleep 2
    done
else
    echo "No Running or Failed deployments found in $RESOURCE_GROUP."
fi

# 2. Delete Deployment Scripts
SCRIPTS=$(az resource list --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Resources/deploymentScripts --query "[].name" -o tsv 2>/dev/null)
if [ -n "$SCRIPTS" ]; then
    echo "Deleting deployment scripts..."
    for SCRIPT in $SCRIPTS; do
        echo "Deleting script: $SCRIPT"
        az resource delete --resource-group "$RESOURCE_GROUP" --name "$SCRIPT" --resource-type Microsoft.Resources/deploymentScripts  || {
            echo "Warning: Failed to delete $SCRIPT. Trying force delete..."
            az resource delete --resource-group "$RESOURCE_GROUP" --name "$SCRIPT" --resource-type Microsoft.Resources/deploymentScripts --force  2>/dev/null || {
                echo "Error: Could not delete $SCRIPT. Check permissions or open a support ticket."
            }
        }
        sleep 2
    done
else
    echo "No deployment scripts found in $RESOURCE_GROUP."
fi

# 3. Delete Supporting Storage Accounts
STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null)
if [ -n "$STORAGE_ACCOUNTS" ]; then
    echo "Deleting Storage Accounts..."
    for SA in $STORAGE_ACCOUNTS; do
        echo "Deleting Storage Account: $SA"
        az storage account delete --resource-group "$RESOURCE_GROUP" --name "$SA"  || {
            echo "Warning: Failed to delete $SA. Skipping..."
        }
        sleep 2
    done
else
    echo "No Storage Accounts found in $RESOURCE_GROUP."
fi

# 4. Delete Supporting Container Instances
CONTAINERS=$(az container list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null)
if [ -n "$CONTAINERS" ]; then
    echo "Deleting Container Instances..."
    for CONTAINER in $CONTAINERS; do
        echo "Deleting Container Instance: $CONTAINER"
        az container delete --resource-group "$RESOURCE_GROUP" --name "$CONTAINER"  || {
            echo "Warning: Failed to delete $CONTAINER. Skipping..."
        }
        sleep 2
    done
else
    echo "No Container Instances found in $RESOURCE_GROUP."
fi

# 5. Verify Cleanup
echo "Verifying cleanup..."
az deployment group list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, State:properties.provisioningState}" -o table
az resource list --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Resources/deploymentScripts --query "[].name" -o tsv
az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv
az container list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv

echo "Cleanup of stuck resources in $RESOURCE_GROUP completed."