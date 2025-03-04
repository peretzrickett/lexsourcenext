#!/bin/bash

# File paths
TEMPLATE_FILE="main.bicep"
PARAMS_FILE="clients.json"
OUTPUT_FILE="errors.json"
WINNER_SOUND="dingding.mp3"  # Example winner sound (adjust path)
LOSER_SOUND="nocigar.mp3"  # Example loser sound (adjust path)
DEPLOYMENT_NAME="bicep-$(date +%Y%m%d%H%M%S)"

# Function to play sound (uses macOS afplay, fallback to other players)
play_sound() {
    local sound_file=$1
    
    # Check if the sound file exists
    if [ ! -f "$sound_file" ]; then
        echo "Sound file not found: $sound_file"
        return 1
    fi
    
    # Try to play the sound with available players
    if command -v afplay &> /dev/null; then
        afplay "$sound_file" &>/dev/null &
    elif command -v paplay &> /dev/null; then
        paplay "$sound_file" &>/dev/null &
    elif command -v play &> /dev/null; then
        play "$sound_file" &>/dev/null &
    else
        echo "Sound playback not supported (no compatible player found)"
        return 1
    fi
    
    # Give a small delay to let the sound start playing
    sleep 0.5
    return 0
}

# Check prerequisites
if ! command -v az &> /dev/null; then
    echo "Error: Azure CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Warning: jq is not installed. Error output will not be formatted nicely."
    # Define simplified jq function if not available
    jq() {
        cat -
    }
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    echo "Error: You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Verify input files exist
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file '$TEMPLATE_FILE' not found."
    exit 1
fi

if [ ! -f "$PARAMS_FILE" ]; then
    echo "Error: Parameters file '$PARAMS_FILE' not found."
    exit 1
fi

# First validate the template
echo "Validating template..."
VALIDATION_OUTPUT=$(az deployment sub validate --location eastus --template-file "$TEMPLATE_FILE" --parameters "@$PARAMS_FILE" 2>&1)
VALIDATION_STATUS=$?

if [ $VALIDATION_STATUS -ne 0 ]; then
    echo "Template validation failed!"
    echo "$VALIDATION_OUTPUT" | tee "$OUTPUT_FILE"
    play_sound "$LOSER_SOUND"
    exit 1
fi

echo "Template validated successfully!"

# Run Azure deployment with progress output
echo "Deploying Azure resources with $TEMPLATE_FILE and $PARAMS_FILE..."
echo "Deployment name: $DEPLOYMENT_NAME"

# Ask user if they want to run a what-if simulation first
read -p "Run a what-if deployment simulation first? (y/n): " RUN_WHATIF
if [[ $RUN_WHATIF == "y" || $RUN_WHATIF == "Y" ]]; then
    echo "Running what-if analysis..."
    az deployment sub what-if \
        --location eastus \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMS_FILE"
    
    # Confirm deployment
    read -p "Proceed with actual deployment? (y/n): " PROCEED
    if [[ $PROCEED != "y" && $PROCEED != "Y" ]]; then
        echo "Deployment cancelled by user."
        exit 0
    fi
fi

# Set maximum deployment time (in seconds)
TIMEOUT=1800  # 30 minutes

echo "Starting deployment..."
# Check if timeout command is available
if command -v timeout &> /dev/null; then
    echo "Using timeout command with $TIMEOUT second limit..."
    timeout $TIMEOUT az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location eastus \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMS_FILE" \
        2>&1 | tee deployment_output.log
else
    # Use a background job with trap for clean termination
    echo "Timeout command not available, using background job with time limit of $TIMEOUT seconds..."
    
    # Create a function to kill the deployment process
    cleanup() {
        if [ -n "$DEPLOYMENT_PID" ]; then
            echo "Killing deployment process..."
            kill $DEPLOYMENT_PID 2>/dev/null || true
            wait $DEPLOYMENT_PID 2>/dev/null || true
            az deployment sub cancel --name "$DEPLOYMENT_NAME" 2>/dev/null || true
        fi
    }
    
    # Set up trap to clean up on script exit
    trap cleanup EXIT INT TERM
    
    # Start deployment in background
    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location eastus \
        --template-file "$TEMPLATE_FILE" \
        --parameters "@$PARAMS_FILE" \
        > deployment_output.log 2>&1 &
    DEPLOYMENT_PID=$!
    
    # Wait for completion or timeout
    SECONDS=0
    echo "Deployment running in background (PID: $DEPLOYMENT_PID)..."
    echo "Tailing log file (Ctrl+C to stop waiting but continue deployment)..."
    
    # Monitor for completion or timeout with polling
    (
        tail -f deployment_output.log &
        TAIL_PID=$!
        
        echo "Monitoring deployment status..."
        STATUS="Running"
        POLL_INTERVAL=20  # Seconds between status checks
        
        # Wait for the deployment to complete or timeout
        while [ "$STATUS" = "Running" ] || [ "$STATUS" = "Accepted" ]; do
            if [ $SECONDS -gt $TIMEOUT ]; then
                echo "Deployment time limit ($TIMEOUT seconds) reached. Deployment continues in background."
                echo "You can check status with: az deployment sub show --name \"$DEPLOYMENT_NAME\" --query \"properties.provisioningState\""
                break
            fi
            
            # Check if the process is still running
            if ! kill -0 $DEPLOYMENT_PID 2>/dev/null; then
                echo "Deployment process completed, checking final status..."
                break
            fi
            
            # Poll for deployment status
            if (( SECONDS % POLL_INTERVAL == 0 )); then
                echo "Polling deployment status (${SECONDS}s elapsed)..."
                POLL_STATUS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.provisioningState" -o tsv 2>/dev/null)
                if [ -n "$POLL_STATUS" ]; then
                    STATUS="$POLL_STATUS"
                    echo "Current deployment status: $STATUS"
                    
                    # If deployment succeeded or failed, we're done
                    if [ "$STATUS" = "Succeeded" ] || [ "$STATUS" = "Failed" ] || [ "$STATUS" = "Canceled" ]; then
                        echo "Deployment finished with status: $STATUS"
                        break
                    fi
                fi
            fi
            
            sleep 1
        done
        
        # Kill the tail process when done
        kill $TAIL_PID 2>/dev/null || true
        
        # Get final status if we didn't break out due to timeout
        if [ $SECONDS -le $TIMEOUT ]; then
            FINAL_STATUS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.provisioningState" -o tsv 2>/dev/null)
            if [ -n "$FINAL_STATUS" ]; then
                echo "Final deployment status: $FINAL_STATUS"
                STATUS="$FINAL_STATUS"
            fi
        fi
        
        # Set exit code based on deployment status
        if [ "$STATUS" = "Succeeded" ]; then
            exit 0
        else
            exit 1
        fi
    )
    
    # Get the status from the subshell
    POLL_STATUS=$?
    
    # Check if deployment process is still running
    if kill -0 $DEPLOYMENT_PID 2>/dev/null; then
        echo "Deployment is still running in the background."
        echo "To check status: az deployment sub show --name \"$DEPLOYMENT_NAME\" --query \"properties.provisioningState\""
        echo "To cancel: az deployment sub cancel --name \"$DEPLOYMENT_NAME\""
        # Detach the PID so the trap doesn't kill it when the script exits
        DEPLOYMENT_PID=""
        exit 0
    else
        # Collect the deployment status
        wait $DEPLOYMENT_PID
        DEPLOYMENT_STATUS=$?
        
        # Use polling status if available
        if [ $POLL_STATUS -ne 0 ]; then
            DEPLOYMENT_STATUS=$POLL_STATUS
        fi
    fi
    
    # Display full log at the end
    cat deployment_output.log
    
    # Get final deployment status from Azure
    FINAL_STATUS=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.provisioningState" -o tsv 2>/dev/null)
    if [ -n "$FINAL_STATUS" ]; then
        echo "Final deployment status from Azure: $FINAL_STATUS"
        if [ "$FINAL_STATUS" = "Failed" ]; then
            DEPLOYMENT_STATUS=1
        elif [ "$FINAL_STATUS" = "Succeeded" ]; then
            DEPLOYMENT_STATUS=0
        fi
    fi
    
    # Check for non-critical errors like RoleAssignmentExists
    ERROR_OUTPUT=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.error" -o json 2>/dev/null)
    if [ -n "$ERROR_OUTPUT" ] && echo "$ERROR_OUTPUT" | grep -q "RoleAssignmentExists"; then
        echo "Detected non-critical error: Role assignment already exists. Treating as success."
        DEPLOYMENT_STATUS=0
    fi
fi

# Get deployment status - use first PIPESTATUS for timeout version, or the stored DEPLOYMENT_STATUS for background version
if [ -n "${PIPESTATUS[0]}" ]; then
    DEPLOYMENT_STATUS=${PIPESTATUS[0]}
fi

# Check deployment status
if [ $DEPLOYMENT_STATUS -eq 0 ]; then
    echo "Deployment succeeded!"
    play_sound "$WINNER_SOUND"
    
    # Show deployment outputs
    echo "Deployment outputs:"
    az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.outputs" -o json | jq '.'
else
    echo "Deployment failed!"
    play_sound "$LOSER_SOUND"

    # Get and format error details
    ERROR_JSON=$(az deployment sub show --name "$DEPLOYMENT_NAME" --query "properties.error" -o json 2>/dev/null)
    if [ -n "$ERROR_JSON" ]; then
        # Save formatted JSON to file
        echo "$ERROR_JSON" | jq '.' > "$OUTPUT_FILE"
        echo "Error details saved to $OUTPUT_FILE"
        
        # Display formatted error summary
        echo "Error summary:"
        echo "$ERROR_JSON" | jq '.'
    else
        # Fallback to log file if API doesn't return error details
        cat deployment_output.log > "$OUTPUT_FILE"
        echo "Error details saved to $OUTPUT_FILE"
        
        # Try to extract error message for console output
        echo "Error summary (raw log):"
        grep -A 5 "\"error\":" deployment_output.log | head -n 10 || echo "Could not parse error details"
    fi
fi

# Clean up temp file
rm -f deployment_output.log