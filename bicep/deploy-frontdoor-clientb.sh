#!/bin/bash
# Script to create Azure Front Door components for ClientB using the same settings
# that were successful in our manual configuration

set -e

echo "=== Creating Front Door components for ClientB ==="

# Configuration
RESOURCE_GROUP="rg-central"
FRONTDOOR_NAME="globalFrontDoor"
DISCRIMINATOR="lexsb"
CLIENT="ClientB"
SUBSCRIPTION_ID="ed42d05a-0eb7-4618-b08d-495f9f21ab85"

# Derived variables
ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
ENDPOINT_NAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
ROUTE_NAME="afd-rt-${DISCRIMINATOR}-${CLIENT}"
ORIGIN_HOST="app-${DISCRIMINATOR}-${CLIENT}.azurewebsites.net"
CLIENT_RG="rg-${CLIENT}"
APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"

# Ensure subscription is set
echo "Setting subscription..."
az account set --subscription $SUBSCRIPTION_ID

# Check Front Door profile
echo "Checking if Front Door profile exists..."
FD_EXISTS=$(az afd profile show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --query "id" -o tsv 2>/dev/null) || FD_EXISTS=""

if [ -z "$FD_EXISTS" ]; then
  echo "ERROR: Front Door profile $FRONTDOOR_NAME does not exist in $RESOURCE_GROUP"
  echo "Please ensure the profile is created first."
  exit 1
fi

echo "Front Door profile confirmed: $FD_EXISTS"

# Check if origin group already exists
echo "Checking if origin group exists..."
OG_EXISTS=$(az afd origin-group show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --origin-group-name $ORIGIN_GROUP --query "id" -o tsv 2>/dev/null) || OG_EXISTS=""

if [ -n "$OG_EXISTS" ]; then
  echo "Origin group $ORIGIN_GROUP already exists. Skipping creation."
else
  # Create origin group
  echo "Creating origin group: $ORIGIN_GROUP"
  az afd origin-group create \
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
    --session-affinity-state Disabled
  
  echo "Origin group created successfully."
fi

# Check if origin already exists
echo "Checking if origin exists..."
ORIGIN_EXISTS=$(az afd origin show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --origin-group-name $ORIGIN_GROUP --origin-name $ORIGIN_NAME --query "id" -o tsv 2>/dev/null) || ORIGIN_EXISTS=""

if [ -n "$ORIGIN_EXISTS" ]; then
  echo "Origin $ORIGIN_NAME already exists. Skipping creation."
else
  # Create origin with private link
  echo "Creating origin with private link: $ORIGIN_NAME"
  az afd origin create \
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
    --enforce-certificate-name-check true
  
  echo "Origin created successfully."
fi

# Wait for origin to be fully provisioned
echo "Waiting for origin to be fully provisioned (10 seconds)..."
sleep 10

# Check if endpoint already exists
echo "Checking if endpoint exists..."
ENDPOINT_EXISTS=$(az afd endpoint show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --endpoint-name $ENDPOINT_NAME --query "id" -o tsv 2>/dev/null) || ENDPOINT_EXISTS=""

if [ -n "$ENDPOINT_EXISTS" ]; then
  echo "Endpoint $ENDPOINT_NAME already exists. Skipping creation."
else
  # Create endpoint
  echo "Creating endpoint: $ENDPOINT_NAME"
  az afd endpoint create \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --endpoint-name "$ENDPOINT_NAME" \
    --enabled-state Enabled
  
  echo "Endpoint created successfully."
fi

# Check if route already exists
echo "Checking if route exists..."
ROUTE_EXISTS=$(az afd route show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --endpoint-name $ENDPOINT_NAME --route-name $ROUTE_NAME --query "id" -o tsv 2>/dev/null) || ROUTE_EXISTS=""

if [ -n "$ROUTE_EXISTS" ]; then
  echo "Route $ROUTE_NAME already exists. Skipping creation."
else
  # Create route
  echo "Creating route: $ROUTE_NAME"
  az afd route create \
    --resource-group "$RESOURCE_GROUP" \
    --profile-name "$FRONTDOOR_NAME" \
    --endpoint-name "$ENDPOINT_NAME" \
    --route-name "$ROUTE_NAME" \
    --origin-group "$ORIGIN_GROUP" \
    --supported-protocols Http Https \
    --forwarding-protocol MatchRequest \
    --link-to-default-domain Enabled \
    --https-redirect Enabled
  
  echo "Route created successfully."
fi

# Approve private endpoint connection
echo "Checking for private endpoint connections to approve..."
PRIVATE_ENDPOINT_CONNECTIONS=$(az webapp private-endpoint-connection list --resource-group $CLIENT_RG --name $APP_NAME --query "[?contains(properties.privateEndpoint.id, 'Microsoft.Cdn')].name" -o tsv)

if [ -n "$PRIVATE_ENDPOINT_CONNECTIONS" ]; then
  for CONN_NAME in $PRIVATE_ENDPOINT_CONNECTIONS; do
    echo "Approving private endpoint connection: $CONN_NAME"
    az webapp private-endpoint-connection approve --resource-group $CLIENT_RG --name $APP_NAME --id $CONN_NAME \
      || echo "Failed to approve $CONN_NAME, it might already be approved or require manual approval"
  done
else
  echo "No private endpoint connections found for approval."
  echo "You may need to manually approve the connection in the Azure Portal."
fi

# Display Front Door endpoint URL
echo ""
echo "=== Front Door setup completed ==="
ENDPOINT_HOSTNAME=$(az afd endpoint show --resource-group $RESOURCE_GROUP --profile-name $FRONTDOOR_NAME --endpoint-name $ENDPOINT_NAME --query "hostName" -o tsv)
echo "Front Door Endpoint URL: https://$ENDPOINT_HOSTNAME"
echo "NOTE: It may take 15-30 minutes for DNS propagation and private link connections to fully establish."
echo "If you see 404 errors initially, wait and retry later." 