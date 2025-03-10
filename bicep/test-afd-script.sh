#!/bin/bash
set -euo pipefail
echo "==== Starting Test Front Door Script ===="
echo "Running as: $(az account show --query user.name -o tsv)"
echo "Current subscription: $(az account show --query name -o tsv)"
# Test creating an origin group
echo "Creating test origin group..."
az afd origin-group create \
  --resource-group rg-central \
  --profile-name globalFrontDoor \
  --origin-group-name test-script-og \
