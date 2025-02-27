#!/bin/zsh

# Array of resource groups to check
RESOURCE_GROUPS=(rg-central rg-clienta rg-clientb)

# Maximum concurrent processes
MAX_CONCURRENT=3

# Function to process deployments in a resource group
process_resource_group() {
    local RG=$1
    echo "Processing deployments in resource group: $RG"

    # List deployments with Running or Failed state
    echo "Listing deployments in $RG..."
    DEPLOYMENTS=$(az deployment group list --resource-group "$RG" --query "[?properties.provisioningState=='Running' || properties.provisioningState=='Failed'].{Name:name, State:properties.provisioningState}" -o tsv 2>/dev/null)

    if [[ -z "$DEPLOYMENTS" ]]; then
        echo "No Running or Failed deployments found in $RG."
        return 0
    fi

    # Iterate through each deployment and delete it
    echo "Found deployments to delete in $RG:"
    echo "$DEPLOYMENTS" | while read -r DEPLOYMENT; do
        NAME=$(echo "$DEPLOYMENT" | cut -f1)
        STATE=$(echo "$DEPLOYMENT" | cut -f2)
        echo "Deleting deployment: $NAME (State: $STATE)"
        
        az deployment group delete --resource-group "$RG" --name "$NAME" || {
            echo "Warning: Failed to delete deployment $NAME in $RG. Skipping..."
        }
        sleep 2  # Brief pause to avoid rate limiting
    done

    echo "Completed processing deployments in $RG."
}

# Process each resource group with limited concurrency
jobs=()
for RG in $RESOURCE_GROUPS; do
    process_resource_group "$RG" &  # Start in background
    jobs+=( $! )  # Store the PID of the last background process

    # If we have MAX_CONCURRENT or more jobs, wait for one to finish
    if [ ${#jobs[@]} -ge $MAX_CONCURRENT ]; then
        wait $jobs[1]  # Wait for the first job in the array
        # Remove the completed job from the array
        jobs=(${jobs[@]:1})
    fi
done

# Wait for any remaining background jobs
if [ ${#jobs[@]} -gt 0 ]; then
    wait ${jobs[@]}
fi

echo "Cleanup of stuck deployments completed."