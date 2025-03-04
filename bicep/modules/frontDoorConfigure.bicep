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
      RESOURCE_GROUP="$RESOURCE_GROUP"
      FRONTDOOR_NAME="$FRONTDOOR_NAME"
      DISCRIMINATOR="$DISCRIMINATOR"
      SUBSCRIPTION_ID="$SUBSCRIPTION_ID" 
      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"
      
      # Function to check connection status and retry if needed
      approve_private_link() {
        local origin_group=$1
        local origin_name=$2
        local app_id=$3
        local max_attempts=5
        local attempt=1
        local success=false
        
        while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
          echo "Attempt $attempt of $max_attempts to approve private link for $origin_name"
          
          # Check current status
          local origin_info=$(az rest --method GET \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=2024-02-01" \
            --query "properties.sharedPrivateLinkResource" -o json)
          
          local current_status=$(echo "$origin_info" | jq -r '.status // "null"')
          echo "Current private link status: $current_status"
          
          if [ "$current_status" = "Approved" ]; then
            echo "Private link already approved for $origin_name"
            success=true
            break
          fi
          
          # Approve the connection
          echo "Approving private link connection for $origin_name (attempt $attempt)"
          az rest --method PATCH \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=2024-02-01" \
            --headers "Content-Type=application/json" \
            --body "{\"properties\":{\"sharedPrivateLinkResource\":{\"privateLink\":{\"id\":\"${app_id}\"},\"status\":\"Approved\",\"privateLinkLocation\":\"eastus\",\"requestMessage\":\"Approved by deployment script\",\"groupId\":\"sites\"}}}" \
            --output json || echo "Failed to approve on attempt $attempt"
          
          # Wait for approval to process
          echo "Waiting for approval to take effect..."
          sleep 30
          
          # Verify if approval succeeded
          origin_info=$(az rest --method GET \
            --uri "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Cdn/profiles/${FRONTDOOR_NAME}/originGroups/${origin_group}/origins/${origin_name}?api-version=2024-02-01" \
            --query "properties.sharedPrivateLinkResource" -o json)
          
          current_status=$(echo "$origin_info" | jq -r '.status // "null"')
          echo "Status after attempt $attempt: $current_status"
          
          if [ "$current_status" = "Approved" ]; then
            echo "Successfully approved private link for $origin_name"
            success=true
            break
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
        # Front Door components
        ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
        ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
        CLIENT_RG="rg-${CLIENT}"
        APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"
        APP_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${CLIENT_RG}/providers/Microsoft.Web/sites/${APP_NAME}"
        
        echo "Processing Front Door origin: $ORIGIN_NAME to app: $APP_NAME"
        
        # Approve private link with retry logic
        if approve_private_link "$ORIGIN_GROUP" "$ORIGIN_NAME" "$APP_ID"; then
          echo "Private link approval successful for $CLIENT"
          
          # Configure NSG rules to allow Azure Front Door traffic
          echo "Ensuring NSG rules allow Azure Front Door traffic..."
          
          # Get the NSGs for the client
          FRONTEND_NSG="nsg-${DISCRIMINATOR}-${CLIENT}-frontend"
          PRIVATELINK_NSG="nsg-${DISCRIMINATOR}-${CLIENT}-privatelink"
          
          # Add rules to frontend NSG if they don't exist
          AFD_SERVICE_TAG_RULE_EXISTS=$(az network nsg rule list --resource-group "$CLIENT_RG" --nsg-name "$FRONTEND_NSG" --query "[?name=='Allow-AFD-Service'].name" -o tsv)
          if [ -z "$AFD_SERVICE_TAG_RULE_EXISTS" ]; then
            echo "Adding Azure Front Door service tag rule to $FRONTEND_NSG..."
            az network nsg rule create \
              --resource-group "$CLIENT_RG" \
              --nsg-name "$FRONTEND_NSG" \
              --name "Allow-AFD-Service" \
              --access Allow \
              --protocol "*" \
              --direction Inbound \
              --priority 120 \
              --source-address-prefix "AzureFrontDoor.Backend" \
              --destination-address-prefix "*" \
              --destination-port-range "*" \
              --description "Allow traffic from Azure Front Door service tag" || echo "Failed to add service tag rule to $FRONTEND_NSG"
          fi
          
          AFD_MANAGED_RULE_EXISTS=$(az network nsg rule list --resource-group "$CLIENT_RG" --nsg-name "$FRONTEND_NSG" --query "[?name=='Allow-AFD-Managed-Endpoints'].name" -o tsv)
          if [ -z "$AFD_MANAGED_RULE_EXISTS" ]; then
            echo "Adding Azure Front Door managed endpoints rule to $FRONTEND_NSG..."
            az network nsg rule create \
              --resource-group "$CLIENT_RG" \
              --nsg-name "$FRONTEND_NSG" \
              --name "Allow-AFD-Managed-Endpoints" \
              --access Allow \
              --protocol "*" \
              --direction Inbound \
              --priority 110 \
              --source-address-prefix "10.8.0.0/16" \
              --destination-address-prefix "*" \
              --destination-port-range "*" \
              --description "Allow traffic from Azure Front Door managed private endpoints" || echo "Failed to add managed endpoints rule to $FRONTEND_NSG"
          fi
          
          # Similar rules for privatelink NSG
          if [ -n "$PRIVATELINK_NSG" ]; then
            AFD_SERVICE_TAG_RULE_EXISTS=$(az network nsg rule list --resource-group "$CLIENT_RG" --nsg-name "$PRIVATELINK_NSG" --query "[?name=='Allow-AFD-Service'].name" -o tsv)
            if [ -z "$AFD_SERVICE_TAG_RULE_EXISTS" ]; then
              echo "Adding Azure Front Door service tag rule to $PRIVATELINK_NSG..."
              az network nsg rule create \
                --resource-group "$CLIENT_RG" \
                --nsg-name "$PRIVATELINK_NSG" \
                --name "Allow-AFD-Service" \
                --access Allow \
                --protocol "*" \
                --direction Inbound \
                --priority 120 \
                --source-address-prefix "AzureFrontDoor.Backend" \
                --destination-address-prefix "*" \
                --destination-port-range "*" \
                --description "Allow traffic from Azure Front Door service tag" || echo "Failed to add service tag rule to $PRIVATELINK_NSG"
            fi
            
            AFD_MANAGED_RULE_EXISTS=$(az network nsg rule list --resource-group "$CLIENT_RG" --nsg-name "$PRIVATELINK_NSG" --query "[?name=='Allow-AFD-Managed-Endpoints'].name" -o tsv)
            if [ -z "$AFD_MANAGED_RULE_EXISTS" ]; then
              echo "Adding Azure Front Door managed endpoints rule to $PRIVATELINK_NSG..."
              az network nsg rule create \
                --resource-group "$CLIENT_RG" \
                --nsg-name "$PRIVATELINK_NSG" \
                --name "Allow-AFD-Managed-Endpoints" \
                --access Allow \
                --protocol "*" \
                --direction Inbound \
                --priority 110 \
                --source-address-prefix "10.8.0.0/16" \
                --destination-address-prefix "*" \
                --destination-port-range "*" \
                --description "Allow traffic from Azure Front Door managed private endpoints" || echo "Failed to add managed endpoints rule to $PRIVATELINK_NSG"
            fi
          fi
        else
          echo "Failed to approve private link for $CLIENT after multiple attempts"
        fi
        
        # Ensure the webapp is properly configured
        echo "Configuring app: $APP_NAME..."
        
        # Enable alwaysOn for webapp
        az webapp config set \
          --resource-group "$CLIENT_RG" \
          --name "$APP_NAME" \
          --always-on true || echo "Failed to set alwaysOn for $APP_NAME"
          
        # Disable public network access (only after private link is working)
        if [ "$ENABLE_PUBLIC_ACCESS" != "true" ]; then
          echo "Disabling public network access for $APP_NAME..."
          az webapp update \
            --resource-group "$CLIENT_RG" \
            --name "$APP_NAME" \
            --set publicNetworkAccess=Disabled || echo "Failed to disable public network access for $APP_NAME"
        else
          echo "Keeping public network access enabled for $APP_NAME as requested"
        fi
      done
      
      echo "Front Door private link approval and app configuration completed"
      echo "{\"status\": \"completed\"}" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'FRONTDOOR_NAME', value: name }
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
      { name: 'ENABLE_PUBLIC_ACCESS', value: 'false' } // Set to true when troubleshooting
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT30M'  // Increased timeout for retry logic
    cleanupPreference: 'OnSuccess'
  }
  // The dependency is already implicit through the use of configureAFD.properties.outputs
}
