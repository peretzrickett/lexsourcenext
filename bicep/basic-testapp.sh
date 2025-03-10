#!/bin/bash

# Basic test app deployment script
# This script creates an extremely basic index.html and deploys it directly to the App Service

# Variables
RESOURCE_GROUP="rg-ClientB"
APP_NAME="app-lexsb-ClientB"

# Check if App Service exists
echo "Checking if app service $APP_NAME exists in resource group $RESOURCE_GROUP..."
APP_EXISTS=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null)
if [ -z "$APP_EXISTS" ]; then
  echo "App service $APP_NAME not found in resource group $RESOURCE_GROUP. Exiting."
  exit 1
fi

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: $TEMP_DIR"

# Create the most basic index.html possible
echo "Creating basic index.html..."
cat > "$TEMP_DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Basic Test</title>
</head>
<body>
    <h1>Hello World</h1>
    <p>If you can see this, the web app is working.</p>
    <p>Generated at: $(date)</p>
</body>
</html>
EOF

# Create a minimal web.config
echo "Creating basic web.config..."
cat > "$TEMP_DIR/web.config" << EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <directoryBrowse enabled="true" />
    <defaultDocument>
      <files>
        <add value="index.html" />
      </files>
    </defaultDocument>
  </system.webServer>
</configuration>
EOF

# Deploy files directly using FTP
echo "Deploying files directly using az webapp deploy..."
pushd "$TEMP_DIR"
zip -r ../basicapp.zip .
popd

# Use direct ZIP deployment to the App Service
echo "Using ZIP deployment..."
az webapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --src basicapp.zip

# Clean up
echo "Cleaning up..."
rm -rf "$TEMP_DIR"
rm -f basicapp.zip

echo "Deployment completed!"
echo "App should be accessible at: https://$APP_NAME.azurewebsites.net"
echo "Testing connectivity:"
curl -k https://$APP_NAME.azurewebsites.net 