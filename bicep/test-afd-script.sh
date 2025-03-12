#!/bin/bash
set -euo pipefail

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

echo "==== Starting Test Front Door Script ===="
echo "Running as: $(az account show --query user.name -o tsv)"
echo "Current subscription: $(az account show --query name -o tsv)"

# Test creating an origin group
echo "Creating test origin group..."
az afd origin-group create \
  --resource-group rg-${DISCRIMINATOR}-central \
  --profile-name globalFrontDoor \
  --origin-group-name test-script-og \
