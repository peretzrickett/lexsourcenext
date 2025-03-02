#!/bin/bash

# Array of resource groups to check
RESOURCE_GROUPS=(rg-central rg-clienta rg-clientb)

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

# Function to process a single resource group
process_resource_group() {
    local RG=$1
    echo "Starting cleanup of Private DNS Zones in resource group $RG..."

    # Check permissions before proceeding
    check_permissions "$RG"

    # List all Private DNS Zones in the resource group
    echo "Listing Private DNS Zones in $RG..."
    ZONES=$(az network private-dns zone list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null)

    if [[ -z "$ZONES" ]]; then
        echo "No Private DNS Zones found in $RG."
        return 0
    fi

    # Process each zone with limited concurrency
    jobs=()
    for ZONE in $ZONES; do
        (
            echo "Processing Private DNS Zone: $ZONE in $RG"

            # List and delete all virtual network links for the zone
            echo "Listing virtual network links for zone $ZONE in $RG..."
            LINKS=$(az network private-dns link vnet list --resource-group "$RG" --zone-name "$ZONE" --query "[].name" -o tsv 2>/dev/null)

            if [[ -n "$LINKS" ]]; then
                echo "Deleting virtual network links for zone $ZONE in $RG..."
                for LINK in $LINKS; do
                    echo "Attempting to delete link: $LINK"
                    run_az_command "az network private-dns link vnet delete --resource-group '$RG' --zone-name '$ZONE' --name '$LINK' --yes" || {
                        echo "Warning: Failed to delete link $LINK in $RG. Trying to force delete..."
                        run_az_command "az resource delete --resource-group '$RG' --name '$LINK' --resource-type 'Microsoft.Network/privateDnsZones/virtualNetworkLinks' --yes" || {
                            echo "Error: Could not delete link $LINK in $RG. Check permissions, nested resources, or open a support ticket."
                        }
                    }
                    sleep 2  # Short pause to avoid rate limiting
                done
            else
                echo "No virtual network links found for zone $ZONE in $RG."
            fi

            # List and delete only A record sets for the zone
            echo "Listing A record sets for zone $ZONE in $RG..."
            A_RECORDS=$(az network private-dns record-set a list --resource-group "$RG" --zone-name "$ZONE" --query "[].name" -o tsv 2>/dev/null)

            if [[ -n "$A_RECORDS" ]]; then
                echo "Deleting A record sets for zone $ZONE in $RG..."
                for RECORD in $A_RECORDS; do
                    echo "Deleting A record: $RECORD"
                    run_az_command "az network private-dns record-set a delete --resource-group '$RG' --zone-name '$ZONE' --name '$RECORD' --yes" || {
                        echo "Warning: Failed to delete A record $RECORD in $RG. Trying to force delete..."
                        run_az_command "az resource delete --resource-group '$RG' --name '$RECORD' --resource-type 'Microsoft.Network/privateDnsZones/A' --yes" || {
                            echo "Error: Could not delete A record $RECORD in $RG. Check permissions, nested resources, or open a support ticket."
                        }
                    }
                    sleep 2  # Short pause to avoid rate limiting
                done
            else
                echo "No A record sets found for zone $ZONE in $RG."
            fi

            # Wait for links and records to fully delete (increased delay for stability)
            sleep 10

            # Attempt to delete the Private DNS Zone with force
            echo "Attempting to delete Private DNS Zone: $ZONE in $RG"
            run_az_command "az network private-dns zone delete --resource-group '$RG' --name '$ZONE' --yes" || {
                echo "Error: Failed to delete zone $ZONE in $RG. Trying to force delete..."
                run_az_command "az resource delete --resource-group '$RG' --name '$ZONE' --resource-type 'Microsoft.Network/privateDnsZones' --yes" || {
                    echo "Error: Could not delete zone $ZONE in $RG. Check for nested resources, permissions, or open a support ticket."
                }
            }

            echo "Completed processing zone $ZONE in $RG"
        ) &

        # Limit parallel processes to avoid overwhelming Azure API
        if [ ${#jobs[@]} -ge $MAX_CONCURRENT ]; then
            wait $jobs[1]  # Wait for the first (oldest) job to complete
            jobs=(${jobs[@]:1})
        fi
        jobs+=( $! )  # Add the new job's PID to the array
    done

    # Wait for any remaining jobs in this resource group
    if [ ${#jobs[@]} -gt 0 ]; then
        wait ${jobs[@]}
    fi

    echo "Cleanup of Private DNS Zones in $RG completed."
}

# Process each resource group in parallel with limited concurrency
jobs=()
for RG in "${RESOURCE_GROUPS[@]}"; do
    process_resource_group "$RG" &
    jobs+=( $! )  # Store the PID of the background process

    # Limit parallel resource groups to avoid overwhelming Azure API (e.g., 2 concurrent RGs)
    if [ ${#jobs[@]} -ge 2 ]; then
        wait $jobs[1]  # Wait for the first (oldest) job to complete
        jobs=(${jobs[@]:1})
    fi
done

# Wait for all remaining background processes
if [ ${#jobs[@]} -gt 0 ]; then
    wait ${jobs[@]}
fi

echo "Cleanup of all Private DNS Zones completed."