#!/bin/bash

# Script to forcibly cancel all active deployments at subscription level
# Usage: ./cancel-all-deployments.sh [discriminator]
# If discriminator is provided, only cancels deployments in resource groups
# with that discriminator

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-""}
if [ -n "$DISCRIMINATOR" ]; then
    echo "Using discriminator: $DISCRIMINATOR"
    echo "Will only cancel deployments in resource groups with prefix rg-${DISCRIMINATOR}-*"
else
    echo "No discriminator provided. Will cancel deployments in ALL resource groups."
    echo "To target specific deployments, provide a discriminator: ./cancel-all-deployments.sh [discriminator]"
fi

# Get all active deployments at subscription level
echo "Finding active deployments..."
DEPLOYMENTS=$(az deployment sub list --query "[?properties.provisioningState=='Running' || properties.provisioningState=='Accepted'].name" -o tsv)

if [ -z "$DEPLOYMENTS" ]; then
    echo "No active subscription-level deployments found."
else
    echo "Found active deployments to cancel:"
    echo "$DEPLOYMENTS"
    
    # Cancel each active deployment
    for DEPLOYMENT in $DEPLOYMENTS; do
        echo "Cancelling deployment: $DEPLOYMENT"
        az deployment sub cancel --name "$DEPLOYMENT" || {
            echo "Warning: Failed to cancel $DEPLOYMENT. Trying to force delete..."
            az deployment sub delete --name "$DEPLOYMENT" --no-wait || {
                echo "Error: Could not delete $DEPLOYMENT."
            }
        }
        sleep 2
    done
fi

# Now check resource groups for active deployments
echo "Finding resource groups..."
if [ -n "$DISCRIMINATOR" ]; then
    # Only get resource groups with the discriminator prefix
    RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'rg-${DISCRIMINATOR}-')].name" -o tsv)
else
    # Get all resource groups
    RESOURCE_GROUPS=$(az group list --query "[].name" -o tsv)
fi

for RG in $RESOURCE_GROUPS; do
    echo "Checking resource group: $RG"
    
    # Find active deployments in this resource group
    ACTIVE_DEPLOYMENTS=$(az deployment group list --resource-group "$RG" --query "[?properties.provisioningState=='Running' || properties.provisioningState=='Accepted'].name" -o tsv)
    
    if [ -n "$ACTIVE_DEPLOYMENTS" ]; then
        echo "Found active deployments in $RG:"
        echo "$ACTIVE_DEPLOYMENTS"
        
        # Cancel each active deployment
        for DEPLOYMENT in $ACTIVE_DEPLOYMENTS; do
            echo "Cancelling deployment: $DEPLOYMENT in resource group $RG"
            az deployment group cancel --resource-group "$RG" --name "$DEPLOYMENT" || {
                echo "Warning: Failed to cancel $DEPLOYMENT. Trying to force delete..."
                az deployment group delete --resource-group "$RG" --name "$DEPLOYMENT" --no-wait || {
                    echo "Error: Could not delete $DEPLOYMENT in $RG."
                }
            }
            sleep 2
        done
    else
        echo "No active deployments found in $RG."
    fi
done

echo "Deployment cancellation completed. Some deployments may still be in the process of cancelling."
echo "You may need to wait a few minutes before starting a new deployment."