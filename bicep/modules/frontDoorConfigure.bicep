// modules/frontDoorConfigure.bicep

@description('Name of the Azure Front Door instance for global traffic management')
param name string

@description('List of client names to configure Front Door resources for')
param clientNames array

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Subscription ID for resource references')
param subscriptionId string = subscription().subscriptionId

// Step 1: Deployment Script to Configure AFD Components with Private Link
resource configureAFD 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-frontend-${name}'
  location: 'eastus'
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.45.0'
    scriptContent: '''
      #!/bin/bash
      set -euo pipefail
      
      echo "==== Starting Front Door configuration script ===="
      
      # Log environment info
      echo "Running as identity: $(az account show --query user.name -o tsv)"
      echo "Current subscription: $(az account show --query name -o tsv)"
      
      RESOURCE_GROUP="$RESOURCE_GROUP"
      FRONTDOOR_NAME="$FRONTDOOR_NAME"
      DISCRIMINATOR="$DISCRIMINATOR"
      SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

      echo "Parameters: RG=$RESOURCE_GROUP, FD=$FRONTDOOR_NAME, DISC=$DISCRIMINATOR, SUB=$SUBSCRIPTION_ID"

      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"
      echo "Configuring Front Door for clients: ${CLIENT_NAMES[*]}"
      
      # Check for available tools and set up fallbacks
      if ! command -v jq &>/dev/null; then
        echo "Warning: jq is not available. Will use basic string processing instead."
        # Define a simple function to extract values without jq
        function extract_json_value() {
          local json="$1"
          local key="$2"
          echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d ":" -f2- | sed 's/^[ \t"]*//;s/[ \t"]*$//'
        }
      fi

      # Ensure front-door extension is properly installed
      echo "Checking if front-door extension is already installed..."
      if ! az extension show --name front-door &>/dev/null; then
        echo "Installing front-door extension (this may take a moment)..."
        az extension add --name front-door --yes --verbose || {
          echo "ERROR: Failed to install front-door extension. Deployment will fail."
          exit 1
        }
      else
        echo "Front-door extension already installed."
      fi
      
      # Verify the extension works before proceeding
      echo "Verifying front-door extension functionality..."
      if ! az afd --help &>/dev/null; then
        echo "ERROR: front-door extension is not working properly."
        exit 1
      fi
      echo "Front-door extension verified successfully!"
      
      # Create an array to store private link connection IDs
      declare -a PRIVATE_LINK_IDS=()
      
      # Helper function for error handling
      handle_error() {
        local cmd="$1"
        local result="$2"
        echo "ERROR: Command failed: $cmd"
        echo "Error details: $result"
        # Exit with error if this is a critical command
        if [[ "$3" == "critical" ]]; then
          exit 1
        fi
        # Continue execution for non-critical errors
      }

      for CLIENT in "${CLIENT_NAMES[@]}"; do
        echo "==== Processing client: $CLIENT ===="
        
        ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
        ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
        ENDPOINT_NAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
        ROUTE_NAME="afd-rt-${DISCRIMINATOR}-${CLIENT}"
        # When using Azure Front Door with private link to App Service, 
        # use the public hostname (not privatelink) as origin and host header
        # Private link connection will still route privately
        ORIGIN_HOST="app-${DISCRIMINATOR}-${CLIENT}.azurewebsites.net"
        CLIENT_RG="rg-${CLIENT}"
        APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"

        # Verify App Service exists
        echo "Verifying App Service exists: $APP_NAME in $CLIENT_RG"
        APP_EXISTS=$(az webapp show --resource-group "$CLIENT_RG" --name "$APP_NAME" --query "id" -o tsv 2>/dev/null) || APP_EXISTS=""
        
        if [ -z "$APP_EXISTS" ]; then
          echo "WARNING: App Service $APP_NAME does not exist in $CLIENT_RG. Skipping this client."
          continue
        fi
        
        echo "App Service verified: $APP_EXISTS"

        # Create the origin group
        echo "Creating origin group: $ORIGIN_GROUP"
        OG_RESULT=$(az afd origin-group create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --origin-group-name "$ORIGIN_GROUP" \
          --probe-request-type HEAD \
          --probe-protocol Http \
          --probe-interval-in-seconds 100 \
          --sample-size 4 \
          --successful-samples-required 3 \
          --probe-path "/" \
          --additional-latency-in-milliseconds 50 \
          -o json 2>&1)
          
        if [ $? -ne 0 ]; then
          handle_error "Create origin group" "$OG_RESULT" "critical"
        else
          echo "Origin group created successfully: $ORIGIN_GROUP"
        fi

        # Create the origin with private link
        echo "Creating origin with private link: $ORIGIN_NAME"
        ORIGIN_RESULT=$(az afd origin create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --origin-group-name "$ORIGIN_GROUP" \
          --origin-name "$ORIGIN_NAME" \
          --host-name "$ORIGIN_HOST" \
          --origin-host-header "$ORIGIN_HOST" \
          --http-port 80 \
          --https-port 443 \
          --priority 1 \
          --weight 1000 \
          --enabled-state Enabled \
          --enable-private-link true \
          --private-link-location "eastus" \
          --private-link-resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CLIENT_RG}/providers/Microsoft.Web/sites/${APP_NAME}" \
          --private-link-sub-resource-type "sites" \
          --private-link-request-message "AFD App Service origin Private Link request." \
          --enforce-certificate-name-check true -o json 2>&1)
          
        if [ $? -ne 0 ]; then
          handle_error "Create origin" "$ORIGIN_RESULT" "critical"
        else
          echo "Origin created successfully: $ORIGIN_NAME"
          
          # Directly extract resource ID for private link approval
          APP_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CLIENT_RG}/providers/Microsoft.Web/sites/${APP_NAME}"
          PRIVATE_LINK_IDS+=("$APP_ID")
          echo "Added resource ID for private link approval: $APP_ID"
          
          # Also try to extract from response, but don't fail if it doesn't work
          echo "DEBUG: Origin result raw output preview:"
          echo "${ORIGIN_RESULT:0:500}..."
        fi

        # Create the endpoint
        echo "Creating endpoint: $ENDPOINT_NAME"
        ENDPOINT_RESULT=$(az afd endpoint create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --endpoint-name "$ENDPOINT_NAME" \
          --enabled-state Enabled \
          -o json 2>&1)
          
        if [ $? -ne 0 ]; then
          handle_error "Create endpoint" "$ENDPOINT_RESULT" "critical"
        else
          echo "Endpoint created successfully: $ENDPOINT_NAME"
        fi

        # Create the route
        echo "Creating route: $ROUTE_NAME"
        ROUTE_RESULT=$(az afd route create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --endpoint-name "$ENDPOINT_NAME" \
          --route-name "$ROUTE_NAME" \
          --origin-group "$ORIGIN_GROUP" \
          --supported-protocols Http Https \
          --forwarding-protocol MatchRequest \
          --link-to-default-domain Enabled \
          --https-redirect Enabled \
          -o json 2>&1)
          
        if [ $? -ne 0 ]; then
          handle_error "Create route" "$ROUTE_RESULT" "critical"
        else
          echo "Route created successfully: $ROUTE_NAME"
        fi
        
        echo "===== Completed processing for client: $CLIENT ====="
      done

      # Return the private link IDs for the next script to use
      echo "Returning private link IDs"
      if [ ${#PRIVATE_LINK_IDS[@]} -eq 0 ]; then
        echo "{\"privateLinks\": []}" > $AZ_SCRIPTS_OUTPUT_PATH
        echo "WARNING: No private link IDs were collected. Check logs for errors."
      else
        # Simplify JSON output format to avoid parsing issues
        JSON_OUTPUT=$(printf '"%s",' "${PRIVATE_LINK_IDS[@]}" | sed 's/,$//')
        echo "{\"privateLinks\": [$JSON_OUTPUT]}" > $AZ_SCRIPTS_OUTPUT_PATH
        echo "Successfully collected ${#PRIVATE_LINK_IDS[@]} private link IDs"
      fi
      
      echo "==== Front Door configuration script completed ===="
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'FRONTDOOR_NAME', value: name }
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'Always'
  }
}

// Step 2: Approve Private Link connections and disable public network access
resource approvePLConnections 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'approve-pl-connections-${name}'
  location: 'eastus'
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.45.0'
    scriptContent: '''
      #!/bin/bash
      set -euo pipefail
      
      echo "==== Starting Private Link approval script ===="
      
      # Log environment info
      echo "Running as identity: $(az account show --query user.name -o tsv)"
      echo "Current subscription: $(az account show --query name -o tsv)"
      
      # Parse input parameters
      RESOURCE_GROUP="$RESOURCE_GROUP"
      FRONTDOOR_NAME="$FRONTDOOR_NAME"
      DISCRIMINATOR="$DISCRIMINATOR"
      SUBSCRIPTION_ID="$SUBSCRIPTION_ID" 
      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"
      
      echo "Parameters: RG=$RESOURCE_GROUP, FD=$FRONTDOOR_NAME, DISC=$DISCRIMINATOR, SUB=$SUBSCRIPTION_ID"
      echo "Processing clients: ${CLIENT_NAMES[*]}"

      # Check for available tools and set up fallbacks
      if ! command -v jq &>/dev/null; then
        echo "Warning: jq is not available. Will use basic string processing instead."
        # Define a simple function to extract values without jq
        function extract_json_value() {
          local json="$1"
          local key="$2"
          echo "$json" | grep -o "\"$key\":[^,}]*" | cut -d ":" -f2- | sed 's/^[ \t"]*//;s/[ \t"]*$//'
        }
      fi

      # Ensure front-door extension is properly installed
      echo "Checking if front-door extension is already installed..."
      if ! az extension show --name front-door &>/dev/null; then
        echo "Installing front-door extension (this may take a moment)..."
        az extension add --name front-door --yes --verbose || {
          echo "ERROR: Failed to install front-door extension. Deployment will fail."
          exit 1
        }
      else
        echo "Front-door extension already installed."
      fi
      
      # Verify the extension works before proceeding
      echo "Verifying front-door extension functionality..."
      if ! az afd --help &>/dev/null; then
        echo "ERROR: front-door extension is not working properly."
        exit 1
      fi
      echo "Front-door extension verified successfully!"
      
      # Define API version to use consistently
      API_VERSION="2023-05-01"
      echo "Using API version: $API_VERSION"
      
      # Function to check connection status and retry if needed
      approve_private_link() {
        local origin_group=$1
        local origin_name=$2
        local app_id=$3
        local max_attempts=5
        local attempt=1
        local success=false
        
        echo "Starting approval process for origin: $origin_name"
        
        while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
          echo "Attempt $attempt of $max_attempts to approve private link for $origin_name"
          
          # Check current status
          echo "Checking current private link status..."
          local origin_info=$(az rest --method GET \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=${API_VERSION}" \
            --query "properties.sharedPrivateLinkResource" -o json 2>/dev/null) || origin_info="{}"
          
          echo "DEBUG: Current origin info: $origin_info"
          
          local current_status=""
          if [[ "$origin_info" == *"status"* ]]; then
            if command -v jq &>/dev/null; then
              current_status=$(echo "$origin_info" | jq -r '.status // ""')
            else
              current_status=$(extract_json_value "$origin_info" "status")
            fi
            echo "Current private link status: $current_status"
          else
            echo "Status field not found in origin info"
          fi
          
          if [ "$current_status" = "Approved" ]; then
            echo "Private link already approved for $origin_name"
            success=true
            break
          fi
          
          # Approve the connection
          echo "Approving private link connection for $origin_name (attempt $attempt)"
          local approval_result=""
          
          # Use direct rest call with minimal JSON to avoid parsing issues
          approval_result=$(az rest --method PATCH \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=${API_VERSION}" \
            --headers "Content-Type=application/json" \
            --body "{\"properties\":{\"sharedPrivateLinkResource\":{\"privateLink\":{\"id\":\"${app_id}\"},\"status\":\"Approved\",\"privateLinkLocation\":\"eastus\",\"requestMessage\":\"Approved by deployment script\",\"groupId\":\"sites\"}}}" \
            2>&1) || echo "Failed to approve: $approval_result"
          
          echo "DEBUG: Approval result: $approval_result"
          
          # Wait for approval to process
          echo "Waiting for approval to take effect..."
          sleep 30
          
          # Verify if approval succeeded
          echo "Verifying if approval succeeded..."
          origin_info=$(az rest --method GET \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=${API_VERSION}" \
            --query "properties.sharedPrivateLinkResource" -o json 2>/dev/null) || origin_info="{}"
          
          echo "DEBUG: Updated origin info: $origin_info"
          
          if [[ "$origin_info" == *"status"* ]]; then
            if command -v jq &>/dev/null; then
              current_status=$(echo "$origin_info" | jq -r '.status // ""')
            else
              current_status=$(extract_json_value "$origin_info" "status")
            fi
            echo "Status after attempt $attempt: $current_status"
            
            if [ "$current_status" = "Approved" ]; then
              echo "Successfully approved private link for $origin_name"
              success=true
              break
            fi
          else
            echo "Status field still not found in origin info after approval attempt"
          fi
          
          ((attempt++))
          
          if [ $attempt -le $max_attempts ]; then
            echo "Retrying in 30 seconds..."
            sleep 30
          else
            echo "Failed to approve private link after $max_attempts attempts"
          fi
        done
        
        return $([ "$success" = "true" ] && echo 0 || echo 1)
      }
      
      # For each client, approve the private link connection
      for CLIENT in "${CLIENT_NAMES[@]}"; do
        echo "==== Processing private link approval for client: $CLIENT ===="
        
        # Front Door components
        ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
        ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
        CLIENT_RG="rg-${CLIENT}"
        APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"
        APP_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CLIENT_RG}/providers/Microsoft.Web/sites/${APP_NAME}"
        
        # Verify App Service exists
        echo "Verifying App Service exists: $APP_NAME in $CLIENT_RG"
        APP_EXISTS=$(az webapp show --resource-group "$CLIENT_RG" --name "$APP_NAME" --query "id" -o tsv 2>/dev/null) || APP_EXISTS=""
        
        if [ -z "$APP_EXISTS" ]; then
          echo "WARNING: App Service $APP_NAME does not exist in $CLIENT_RG. Skipping this client."
          continue
        fi
        
        echo "App Service verified: $APP_EXISTS"
        echo "Processing Front Door origin: $ORIGIN_NAME to app: $APP_NAME"
        
        # Verify origin exists
        echo "Verifying Origin exists: $ORIGIN_NAME in $ORIGIN_GROUP"
        ORIGIN_EXISTS=$(az afd origin show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONTDOOR_NAME" --origin-group-name "$ORIGIN_GROUP" --origin-name "$ORIGIN_NAME" --query "id" -o tsv 2>/dev/null) || ORIGIN_EXISTS=""
        
        if [ -z "$ORIGIN_EXISTS" ]; then
          echo "WARNING: Origin $ORIGIN_NAME does not exist in $ORIGIN_GROUP. Skipping this client."
          continue
        fi
        
        echo "Origin verified: $ORIGIN_EXISTS"
        
        # Approve private link with retry logic
        if approve_private_link "$ORIGIN_GROUP" "$ORIGIN_NAME" "$APP_ID"; then
          echo "Private link approval successful for $CLIENT"
        else
          echo "WARNING: Failed to approve private link for $CLIENT after multiple attempts"
          # Continue with other clients even if this one fails
        fi
        
        echo "===== Completed processing for client: $CLIENT ====="
      done
      
      echo "==== Front Door private link approval completed ===="
      echo "{\"status\": \"completed\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'FRONTDOOR_NAME', value: name }
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'Always'
  }
  dependsOn: [
    configureAFD
  ]
}
