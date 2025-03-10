#!/bin/bash

# Simple test app deployment script
# This script deploys a simple HTML page to the App Service

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

# Create temporary folder
echo "Creating temporary deployment folder..."
TEMP_DIR="simple_deploy_temp"
mkdir -p $TEMP_DIR/wwwroot

# Create simple HTML file
echo "Creating basic HTML test page..."
cat > $TEMP_DIR/wwwroot/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Simple Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            line-height: 1.6;
            background-color: #f0f0f0;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: white;
        }
        .timestamp {
            color: #666;
            font-size: 0.8em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Hello from Azure App Service!</h1>
        <p>This is a simple test page to verify direct connectivity to the App Service.</p>
        <p>If you can see this page, the App Service is accessible directly.</p>
        <p class="timestamp">Page generated at: $(date)</p>
    </div>
</body>
</html>
EOF

# Create web.config file for proper routing
echo "Creating web.config file..."
cat > $TEMP_DIR/wwwroot/web.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <staticContent>
      <mimeMap fileExtension=".html" mimeType="text/html" />
    </staticContent>
    <rewrite>
      <rules>
        <rule name="Root Hit Redirect" stopProcessing="true">
          <match url="^$" />
          <action type="Redirect" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
EOF

# Create zip package for deployment
echo "Creating deployment package..."
cd $TEMP_DIR
zip -r ../simple-testapp.zip wwwroot
cd ..

# Deploy directly to App Service using ZIP deploy
echo "Deploying to App Service using ZIP deploy..."
az webapp deployment source config-zip --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --src "simple-testapp.zip"

# Cleanup
echo "Cleaning up..."
rm -rf $TEMP_DIR
rm -f simple-testapp.zip

echo "Deployment completed!"
echo "App should be accessible at: https://$APP_NAME.azurewebsites.net"
echo "Testing connectivity:"
curl -k https://$APP_NAME.azurewebsites.net 