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
    azCliVersion: '2.40.0'
    scriptContent: '''
      #!/bin/bash
      set -ex

      RESOURCE_GROUP="$RESOURCE_GROUP"
      FRONTDOOR_NAME="$FRONTDOOR_NAME"
      DISCRIMINATOR="$DISCRIMINATOR"
      SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"

      az config set extension.use_dynamic_install=yes_without_prompt

      # Create an array to store private link connection IDs
      declare -a PRIVATE_LINK_IDS=()

      for CLIENT in "${CLIENT_NAMES[@]}"; do
        ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
        ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
        ENDPOINT_NAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
        ROUTE_NAME="afd-rt-${DISCRIMINATOR}-${CLIENT}"
        ORIGIN_HOST="app-${DISCRIMINATOR}-${CLIENT}.privatelink.azurewebsites.net"
        CLIENT_RG="rg-${CLIENT}"
        APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"

        # Create the origin group
        echo "Creating origin group: $ORIGIN_GROUP"
        az afd origin-group create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --origin-group-name "$ORIGIN_GROUP" \
          --probe-request-type GET \
          --probe-protocol Https \
          --probe-interval-in-seconds 30 \
          --sample-size 4 \
          --successful-samples-required 3 \
          --probe-path "/" \
          --additional-latency-in-milliseconds 50

        # Create the origin with private link
        echo "Creating origin with private link: $ORIGIN_NAME"
        OUTPUT=$(az afd origin create \
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
          --enforce-certificate-name-check true -o json)

        # Extract private link connection ID
        echo "Extracting private link ID"
        PL_ID=$(echo "$OUTPUT" | jq -r '.privateLinkResource.id')
        if [ -n "$PL_ID" ]; then
          PRIVATE_LINK_IDS+=("$PL_ID")
          echo "Added private link ID: $PL_ID"
        else
          echo "WARNING: Failed to extract private link ID for $CLIENT"
        fi

        # Create the endpoint
        echo "Creating endpoint: $ENDPOINT_NAME"
        az afd endpoint create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --endpoint-name "$ENDPOINT_NAME" \
          --enabled-state Enabled

        # Create the route
        echo "Creating route: $ROUTE_NAME"
        az afd route create \
          --resource-group "$RESOURCE_GROUP" \
          --profile-name "$FRONTDOOR_NAME" \
          --endpoint-name "$ENDPOINT_NAME" \
          --route-name "$ROUTE_NAME" \
          --origin-group "$ORIGIN_GROUP" \
          --supported-protocols Https \
          --forwarding-protocol HttpsOnly \
          --link-to-default-domain Enabled \
          --https-redirect Disabled
      done

      # Return the private link IDs for the next script to use
      echo "Returning private link IDs"
      if [ ${#PRIVATE_LINK_IDS[@]} -eq 0 ]; then
        echo "{\"privateLinks\": []}" > $AZ_SCRIPTS_OUTPUT_PATH
      else
        # Ensure proper JSON formatting with jq
        JSON_OUTPUT=$(printf '"%s",' "${PRIVATE_LINK_IDS[@]}" | sed 's/,$//')
        echo "{\"privateLinks\": [$JSON_OUTPUT]}" | jq '.' > $AZ_SCRIPTS_OUTPUT_PATH
      fi
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'FRONTDOOR_NAME', value: name }
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
  }
}

// Step 2: Approve Private Link connections and disable public network access
resource approvePLConnections 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'approve-pl-connections'
  location: 'eastus'
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      #!/bin/bash
      set -ex
      
      # Parse input parameters
      DISCRIMINATOR="$DISCRIMINATOR"
      SUBSCRIPTION_ID="$SUBSCRIPTION_ID" 
      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"
      
      # Parse private link IDs from previous script
      PRIVATE_LINKS_JSON=$PRIVATE_LINKS
      PRIVATE_LINKS=$(echo "$PRIVATE_LINKS_JSON" | jq -r '.privateLinks[]' 2>/dev/null || echo "")
      
      # Function to wait for private endpoint connection to be created
      wait_for_pe_connection() {
        local app_id=$1
        local max_attempts=30
        local attempt=0
        local found=false
        
        echo "Waiting for private endpoint connection to be created for $app_id..."
        
        while [ $attempt -lt $max_attempts ] && [ "$found" = false ]; do
          connections=$(az network private-endpoint-connection list --id "$app_id" -o json 2>/dev/null || echo "[]")
          connection_count=$(echo "$connections" | jq 'length')
          
          if [ "$connection_count" -gt 0 ]; then
            found=true
            echo "Private endpoint connection found for $app_id"
          else
            echo "Attempt $((attempt+1))/$max_attempts: No private endpoint connections found yet, waiting..."
            sleep 10
            ((attempt++))
          fi
        done
        
        if [ "$found" = false ]; then
          echo "Failed to find private endpoint connection after $max_attempts attempts"
          return 1
        fi
        
        return 0
      }
      
      # Process each client
      for CLIENT in "${CLIENT_NAMES[@]}"; do
        # App properties
        CLIENT_RG="rg-${CLIENT}"
        APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"
        APP_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CLIENT_RG}/providers/Microsoft.Web/sites/${APP_NAME}"
        
        echo "Processing app: $APP_NAME in resource group: $CLIENT_RG"
        
        # Wait for private endpoint connection to be created
        if wait_for_pe_connection "$APP_ID"; then
          # Approve all pending connections for the app
          echo "Approving private endpoint connections for $APP_NAME..."
          
          # Safely retrieve private endpoint connections
          connections=$(az network private-endpoint-connection list --id "$APP_ID" -o json 2>/dev/null || echo "[]")
          # Safely process connections one by one
          echo "$connections" | jq -c '.[]' | while read -r connection; do
            connection_id=$(echo "$connection" | jq -r '.id')
            status=$(echo "$connection" | jq -r '.properties.privateLinkServiceConnectionState.status // "Unknown"')
            
            if [ "$status" != "Approved" ]; then
              echo "Approving connection: $connection_id"
              az network private-endpoint-connection approve \
                --id "$connection_id" \
                --description "Approved by deployment script" || echo "Failed to approve connection: $connection_id"
            else
              echo "Connection already approved: $connection_id"
            fi
          done
          
          # Wait for approval to take effect (10 seconds)
          echo "Waiting for approval to take effect..."
          sleep 10
          
          # Disable public network access for the app
          echo "Disabling public network access for $APP_NAME..."
          az webapp update \
            --resource-group "$CLIENT_RG" \
            --name "$APP_NAME" \
            --set publicNetworkAccess=Disabled || echo "Failed to disable public network access for $APP_NAME"
        else
          echo "Skipping approval for $APP_NAME due to timeout waiting for private endpoint connection"
        fi
      done
      
      echo "Private link approval and public network access configuration completed"
      echo "{\"status\": \"completed\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
      { name: 'PRIVATE_LINKS', value: string(configureAFD.properties.outputs) }
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
  }
  // The dependency is already implicit through the use of configureAFD.properties.outputs
}
