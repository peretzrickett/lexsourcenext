#!/bin/bash

# Configuration variables
CLIENT_NAME="ClientB"
# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

RESOURCE_GROUP="rg-${DISCRIMINATOR}-${CLIENT_NAME}"
LOCATION="eastus"
APP_SERVICE_PLAN="asp-${DISCRIMINATOR}-${CLIENT_NAME}"
APP_SERVICE="app-${DISCRIMINATOR}-${CLIENT_NAME}"
BRANCH="main"

# Define colors for console output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check Azure CLI
check_az() {
    if ! command -v az &> /dev/null; then
        echo -e "${RED}Azure CLI not found. Please install it and run 'az login'.${NC}"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        echo -e "${RED}Not logged in to Azure. Please run 'az login' first.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Azure CLI check passed.${NC}"
}

# Function to check App Service existence
check_app_service() {
    if az webapp show --name "$APP_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        echo -e "${GREEN}App Service $APP_SERVICE exists.${NC}"
        return 0
    else
        echo -e "${YELLOW}App Service $APP_SERVICE does not exist.${NC}"
        return 1
    fi
}

# Function to stop App Service
stop_app_service() {
    echo -e "${YELLOW}Stopping App Service $APP_SERVICE...${NC}"
    az webapp stop --name "$APP_SERVICE" --resource-group "$RESOURCE_GROUP"
    echo -e "${GREEN}App Service stopped.${NC}"
}

# Function to start App Service
start_app_service() {
    echo -e "${YELLOW}Starting App Service $APP_SERVICE...${NC}"
    az webapp start --name "$APP_SERVICE" --resource-group "$RESOURCE_GROUP"
    echo -e "${GREEN}App Service started.${NC}"
}

# Function to deploy code from GitHub
deploy_code() {
    echo -e "${YELLOW}Deploying code to App Service $APP_SERVICE...${NC}"
    
    # Set up deployment source
    az webapp deployment source config --name "$APP_SERVICE" \
                                      --resource-group "$RESOURCE_GROUP" \
                                      --repo-url "https://github.com/azure-samples/nodejs-docs-hello-world" \
                                      --branch "$BRANCH" \
                                      --manual-integration
    
    echo -e "${GREEN}Deployment source configured.${NC}"
    
    # Trigger deployment
    az webapp deployment source sync --name "$APP_SERVICE" \
                                    --resource-group "$RESOURCE_GROUP"
    
    echo -e "${GREEN}Code deployed successfully.${NC}"
}

# Main script execution
echo -e "${YELLOW}=== Starting Simple Test App Deployment ===${NC}"

# Check Azure CLI
check_az

# Check if App Service exists
if check_app_service; then
    # Stop App Service
    stop_app_service
    
    # Deploy code
    deploy_code
    
    # Start App Service
    start_app_service
else
    echo -e "${RED}App Service does not exist. Please create it first.${NC}"
    echo -e "${YELLOW}You can create it using the Azure Portal or Azure CLI.${NC}"
    exit 1
fi

# Get the app URL
APP_URL="https://$APP_SERVICE.azurewebsites.net"
echo -e "${GREEN}Deployment complete. The app should be available at:${NC}"
echo -e "${YELLOW}$APP_URL${NC}"

echo -e "${GREEN}=== Deployment Complete ===${NC}" 