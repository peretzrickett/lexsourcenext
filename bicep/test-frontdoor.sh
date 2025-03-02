#!/bin/bash

# Deploy only the Front Door configuration for testing purposes
echo "Starting Front Door configuration test deployment..."

az deployment sub create \
  --name test-frontdoor-$(date +%Y%m%d%H%M%S) \
  --location eastus \
  --template-file test-frontdoor.bicep \
  --parameters @clients.json

echo "Front Door configuration test deployment completed."