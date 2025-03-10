#!/bin/bash

# Script to deploy a test app to ClientB App Service
# This demonstrates Azure Front Door to Private Link connectivity

echo "Starting deployment of test app to ClientB..."

# Variables
RESOURCE_GROUP="rg-ClientB"
APP_NAME="app-lexsb-ClientB"
STORAGE_ACCOUNT="stglexsbclientb"
CONTAINER_NAME="artifacts"
ZIP_NAME="testapp.zip"

# Get storage account key
STORAGE_KEY=$(az storage account keys list --account-name $STORAGE_ACCOUNT --resource-group $RESOURCE_GROUP --query "[0].value" -o tsv)

# Check if the app service exists
echo "Checking if app service $APP_NAME exists in resource group $RESOURCE_GROUP..."
APP_EXISTS=$(az webapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query name -o tsv 2>/dev/null)

if [ -z "$APP_EXISTS" ]; then
    echo "App service $APP_NAME does not exist in resource group $RESOURCE_GROUP. Exiting."
    exit 1
fi

# Create test HTML file
echo "Creating test HTML file..."
mkdir -p deploy_temp/wwwroot
cat > deploy_temp/wwwroot/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Azure Front Door Private Link Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 40px;
            line-height: 1.6;
        }
        .success {
            color: green;
            font-weight: bold;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Success!</h1>
        <p class="success">Azure Front Door is successfully connected to this App Service via a Private Endpoint.</p>
        <p>This confirms that the private link configuration is working correctly.</p>
        <p>Timestamp: <span id="timestamp"></span></p>
    </div>
    <script>
        document.getElementById('timestamp').textContent = new Date().toISOString();
    </script>
</body>
</html>
EOF

# Create web.config for proper routing
cat > deploy_temp/wwwroot/web.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <staticContent>
      <mimeMap fileExtension=".html" mimeType="text/html" />
    </staticContent>
    <handlers>
      <add name="StaticFile" path="*" verb="*" modules="StaticFileModule" resourceType="File" requireAccess="Read" />
    </handlers>
  </system.webServer>
</configuration>
EOF

# Create a simple hostingstart.html file (this is a special file that Azure App Service looks for)
cat > deploy_temp/wwwroot/hostingstart.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Azure Front Door Private Link Test</title>
</head>
<body>
    <h1>Success! Azure Front Door Private Link Test</h1>
</body>
</html>
EOF

# Create a zip package for deployment
echo "Creating deployment package..."
cd deploy_temp
zip -r ../$ZIP_NAME .
cd ..

# Upload to storage account
echo "Uploading package to storage account $STORAGE_ACCOUNT..."
az storage blob upload --account-name $STORAGE_ACCOUNT --container-name $CONTAINER_NAME --name $ZIP_NAME --file $ZIP_NAME --account-key "$STORAGE_KEY"

# Generate a SAS token for the blob with read permissions
echo "Generating SAS token for the blob..."
END_DATE=$(date -v+1d '+%Y-%m-%dT%H:%MZ')
SAS_TOKEN=$(az storage blob generate-sas --account-name $STORAGE_ACCOUNT --container-name $CONTAINER_NAME --name $ZIP_NAME --permissions r --expiry $END_DATE --account-key "$STORAGE_KEY" -o tsv)

# Get the blob URL with SAS token
BLOB_URL=$(az storage blob url --account-name $STORAGE_ACCOUNT --container-name $CONTAINER_NAME --name $ZIP_NAME --output tsv)
BLOB_URL_WITH_SAS="${BLOB_URL}?${SAS_TOKEN}"
echo "Blob URL with SAS: $BLOB_URL_WITH_SAS"

# Install the package from the storage container
echo "Installing package from storage to App Service..."
az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $APP_NAME --settings WEBSITE_RUN_FROM_PACKAGE="$BLOB_URL_WITH_SAS"

# Clean up
echo "Cleaning up..."
rm -rf deploy_temp
rm -f $ZIP_NAME

echo "Deployment completed successfully!"
echo "App should be available through Front Door endpoint: afd-ep-lexsb-ClientB-fqejbbbsh3c2dpax.z03.azurefd.net"

# Output helpful commands for testing
echo ""
echo "To test connectivity from the VM, run:"
echo "ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@13.92.238.70 \"curl -k https://afd-ep-lexsb-ClientB-fqejbbbsh3c2dpax.z03.azurefd.net\"" 