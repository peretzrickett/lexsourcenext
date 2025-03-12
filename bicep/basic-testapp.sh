#!/bin/bash

# Simple test app deployment script for a basic HTML page

# Variables
CLIENT_NAME="ClientB"
# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

RESOURCE_GROUP="rg-${DISCRIMINATOR}-${CLIENT_NAME}"
APP_NAME="app-${DISCRIMINATOR}-${CLIENT_NAME}"

# Check if App Service exists
echo "Checking if app service $APP_NAME exists in resource group $RESOURCE_GROUP..."
APP_EXISTS=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query "name" -o tsv 2>/dev/null)
if [ -z "$APP_EXISTS" ]; then
  echo "App service $APP_NAME not found in resource group $RESOURCE_GROUP. Exiting."
  exit 1
fi

# Enable public network access
echo "Enabling public network access for the app service..."
az webapp update --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --set publicNetworkAccess=Enabled

# Enable SCM site access
echo "Enabling SCM site access..."
az webapp config access-restriction show --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --query scm -o json
az webapp config access-restriction add --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" \
  --rule-name "Allow All SCM" --action Allow --ip-address "0.0.0.0/0" --priority 100 --scm-site

# Create temporary folder
echo "Creating temporary deployment folder..."
TEMP_DIR="basic_deploy_temp"
mkdir -p $TEMP_DIR/wwwroot

# Create simple HTML file
echo "Creating basic HTML test page..."
cat > $TEMP_DIR/wwwroot/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Basic Test Page</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            line-height: 1.6;
            background-color: #f8f9fa;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .timestamp {
            color: #666;
            font-size: 0.8em;
        }
        .success {
            color: #28a745;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Hello from Azure App Service!</h1>
        <p class="success">✓ Connection Successful</p>
        <p>This is a basic HTML page served from Azure App Service.</p>
        <p>Current timestamp: <span class="timestamp">DATE_PLACEHOLDER</span></p>
        <hr>
        <p>Page deployed using a simple shell script</p>
    </div>
    <script>
        // Update timestamp with browser's current time
        document.querySelector('.timestamp').textContent = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

# Create web.config for proper routing
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

# Create zip package
echo "Creating deployment package..."
cd $TEMP_DIR
zip -r ../basic-testapp.zip wwwroot
cd ..

# Deploy to App Service
echo "Deploying to App Service using ZIP deploy..."
az webapp deploy --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" --src-path "basic-testapp.zip" --type zip

# Cleanup
echo "Cleaning up temporary files..."
rm -rf $TEMP_DIR
rm -f basic-testapp.zip

echo "Deployment completed successfully!"
echo "App should be accessible at: https://$APP_NAME.azurewebsites.net" 