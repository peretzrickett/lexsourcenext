#!/bin/zsh

# Array of resource groups to check
RESOURCE_GROUPS=(rg-central rg-clienta rg-clientb)

# Maximum concurrent processes per resource group
MAX_CONCURRENT=3

# Function to process a single resource group
process_resource_group() {
    local RG=$1
    echo "Starting cleanup of Private DNS Zones in resource group $RG..."

    # List all Private DNS Zones in the resource group
    echo "Listing Private DNS Zones in $RG..."
    ZONES=$(az network private-dns zone list --resource-group "$RG" --query "[].name" -o tsv 2>/dev/null)

    if [[ -z "$ZONES" ]]; then
        echo "No Private DNS Zones found in $RG."
        return 0
    fi

    # Process each zone with limited concurrency
    jobs=()
    for ZONE in ${(f)ZONES}; do  # Split ZONES into array with newlines
        (
            echo "Processing Private DNS Zone: $ZONE in $RG"

            # List and delete all virtual network links for the zone
            echo "Listing virtual network links for zone $ZONE in $RG..."
            LINKS=$(az network private-dns link vnet list --resource-group "$RG" --zone-name "$ZONE" --query "[].name" -o tsv 2>/dev/null)

            if [[ -n "$LINKS" ]]; then
                echo "Deleting virtual network links for zone $ZONE in $RG..."
                for LINK in ${(f)LINKS}; do  # Split LINKS into array with newlines
                    echo "Attempting to delete link: $LINK"
                    az network private-dns link vnet delete --resource-group "$RG" --zone-name "$ZONE" --name "$LINK"  || {
                        echo "Warning: Failed to delete link $LINK in $RG. Trying to force delete..."
                        az resource delete --resource-group "$RG" --name "$LINK" --resource-type "Microsoft.Network/privateDnsZones/virtualNetworkLinks" --yes  2>/dev/null || {
                            echo "Error: Could not delete link $LINK in $RG. Check permissions or nested resources."
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
                for RECORD in ${(f)A_RECORDS}; do  # Split A_RECORDS into array with newlines
                    echo "Deleting A record: $RECORD"
                    az network private-dns record-set a delete --resource-group "$RG" --zone-name "$ZONE" --name "$RECORD"  || {
                        echo "Warning: Failed to delete A record $RECORD in $RG. Trying to force delete..."
                        az resource delete --resource-group "$RG" --name "$RECORD" --resource-type "Microsoft.Network/privateDnsZones/A" --yes  2>/dev/null || {
                            echo "Error: Could not delete A record $RECORD in $RG. Check permissions or nested resources."
                        }
                    }
                    sleep 2  # Short pause to avoid rate limiting
                done
            else
                echo "No A record sets found for zone $ZONE in $RG."
            fi

            # Wait for links and records to fully delete
            sleep 5

            # Attempt to delete the Private DNS Zone with force
            echo "Attempting to delete Private DNS Zone: $ZONE in $RG"
            az network private-dns zone delete --resource-group "$RG" --name "$ZONE"  || {
                echo "Error: Failed to delete zone $ZONE in $RG. Trying to force delete..."
                az resource delete --resource-group "$RG" --name "$ZONE" --resource-type "Microsoft.Network/privateDnsZones" --yes 2>/dev/null || {
                    echo "Error: Could not delete zone $ZONE in $RG. Check for nested resources, permissions, or open a support ticket."
                }
            }

            echo "Completed processing zone $ZONE in $RG"
        ) &

        # Limit parallel processes to avoid overwhelming Azure API (e.g., MAX_CONCURRENT per RG)
        if [ ${#jobs[@]} -ge $MAX_CONCURRENT ]; then
            wait $jobs[1]  # Wait for the first (oldest) job to complete
            # Remove the completed job from the array
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

# Process each resource group in parallel
jobs=()
for RG in $RESOURCE_GROUPS; do
    process_resource_group "$RG" &
    jobs+=( $! )  # Store the PID of the background process

    # Limit parallel processes to avoid overwhelming Azure API (e.g., 3 concurrent RGs)
    if [ ${#jobs[@]} -ge 3 ]; then
        wait $jobs[1]  # Wait for the first (oldest) job to complete
        # Remove the completed job from the array
        jobs=(${jobs[@]:1})
    fi
done

# Wait for all remaining background processes
if [ ${#jobs[@]} -gt 0 ]; then
    wait ${jobs[@]}
fi

echo "Cleanup of all Private DNS Zones completed."