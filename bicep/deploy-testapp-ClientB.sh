#!/bin/bash
# Script to deploy a test web application directly to ClientB App Service
set -e

# Get discriminator from command line argument or use default
DISCRIMINATOR=${1:-"lexsb"}
echo "Using discriminator: $DISCRIMINATOR"

# Configuration
CLIENT_NAME="ClientB"
RESOURCE_GROUP="rg-${DISCRIMINATOR}-${CLIENT_NAME}"
LOCATION="eastus"
APP_SERVICE_PLAN="plan-${DISCRIMINATOR}-${CLIENT_NAME}"
APP_SERVICE="app-${DISCRIMINATOR}-${CLIENT_NAME}"

echo "=== Starting deployment for $CLIENT_NAME with discriminator $DISCRIMINATOR ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "App Service: $APP_SERVICE"

# Check if resource group exists
echo "Checking if resource group exists..."
RG_EXISTS=$(az group exists --name $RESOURCE_GROUP)

if [ "$RG_EXISTS" = "false" ]; then
    echo "Resource group does not exist. Creating resource group $RESOURCE_GROUP in $LOCATION..."
    az group create --name $RESOURCE_GROUP --location $LOCATION
    echo "Resource group created."
else
    echo "Resource group $RESOURCE_GROUP already exists."
fi

# Check if App Service Plan exists
echo "Checking if App Service Plan exists..."
APP_PLAN_EXISTS=$(az appservice plan show --name $APP_SERVICE_PLAN --resource-group $RESOURCE_GROUP --query "name" -o tsv 2>/dev/null) || APP_PLAN_EXISTS=""

if [ -z "$APP_PLAN_EXISTS" ]; then
    echo "App Service Plan does not exist. Creating App Service Plan $APP_SERVICE_PLAN..."
    az appservice plan create \
        --name $APP_SERVICE_PLAN \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --sku B1
    echo "App Service Plan created."
else
    echo "App Service Plan $APP_SERVICE_PLAN already exists."
fi

# Check if App Service exists
echo "Checking if App Service exists..."
APP_EXISTS=$(az webapp show --name $APP_SERVICE --resource-group $RESOURCE_GROUP --query "name" -o tsv 2>/dev/null) || APP_EXISTS=""

if [ -z "$APP_EXISTS" ]; then
    echo "App Service does not exist. Creating App Service $APP_SERVICE..."
    az webapp create \
        --name $APP_SERVICE \
        --resource-group $RESOURCE_GROUP \
        --plan $APP_SERVICE_PLAN \
        --runtime "NODE:16-lts"
    echo "App Service created."
else
    echo "App Service $APP_SERVICE already exists."
fi

# Configure app settings
echo "Configuring app settings..."
az webapp config appsettings set \
    --name $APP_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --settings \
        APP_NAME="$CLIENT_NAME" \
        ENVIRONMENT="Development" \
        WEBSITE_NODE_DEFAULT_VERSION="~16" \
        SCM_DO_BUILD_DURING_DEPLOYMENT="true"

# Create a simple Node.js application with current time
echo "Creating a simple Node.js application..."
DEPLOY_DIR=$(mktemp -d)
cd $DEPLOY_DIR

# Create package.json
cat > package.json << 'EOF'
{
  "name": "simple-node-app",
  "version": "1.0.0",
  "description": "Simple Node.js application for testing",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.17.1",
    "moment": "^2.29.1"
  }
}
EOF

# Create index.js
cat > index.js << 'EOF'
const express = require('express');
const moment = require('moment');
const app = express();
const port = process.env.PORT || 3000;

app.get('/', (req, res) => {
  const appName = process.env.APP_NAME || 'Unknown App';
  const env = process.env.ENVIRONMENT || 'Unknown Environment';
  
  const html = `
  <!DOCTYPE html>
  <html>
  <head>
    <title>${appName} Test App</title>
    <style>
      body {
        font-family: Arial, sans-serif;
        margin: 0;
        padding: 20px;
        background-color: #f0f8ff;
        color: #333;
      }
      .container {
        background-color: white;
        border-radius: 8px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        padding: 20px;
        max-width: 800px;
        margin: 40px auto;
      }
      h1 {
        color: #0078d4;
        border-bottom: 1px solid #eee;
        padding-bottom: 10px;
      }
      .info {
        margin: 20px 0;
        padding: 15px;
        background-color: #e6f7ff;
        border-left: 4px solid #0078d4;
        border-radius: 4px;
      }
      .time {
        font-size: 1.2em;
        margin: 20px 0;
      }
      footer {
        margin-top: 30px;
        font-size: 0.8em;
        color: #666;
        text-align: center;
      }
    </style>
  </head>
  <body>
    <div class="container">
      <h1>${appName} Test Application</h1>
      
      <div class="info">
        <p>Environment: ${env}</p>
        <p>Server: ${req.headers.host}</p>
        <p>Request Path: ${req.path}</p>
      </div>
      
      <div class="time">
        <p>Current Server Time: ${moment().format('YYYY-MM-DD HH:mm:ss')}</p>
      </div>
      
      <div>
        <h3>Request Headers:</h3>
        <pre>${JSON.stringify(req.headers, null, 2)}</pre>
      </div>
      
      <footer>
        ${appName} Test App - Deployed on ${moment().format('YYYY-MM-DD')}
      </footer>
    </div>
  </body>
  </html>
  `;
  
  res.send(html);
});

app.get('/api/info', (req, res) => {
  res.json({
    appName: process.env.APP_NAME || 'Unknown App',
    environment: process.env.ENVIRONMENT || 'Unknown Environment',
    serverTime: moment().format('YYYY-MM-DD HH:mm:ss'),
    serverTimestamp: Date.now(),
  });
});

app.get('/api/headers', (req, res) => {
  res.json({
    headers: req.headers
  });
});

app.listen(port, () => {
  console.log(`App listening at http://localhost:${port}`);
});
EOF

# Create web.config for IIS
cat > web.config << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <system.webServer>
    <webSocket enabled="false" />
    <handlers>
      <add name="iisnode" path="index.js" verb="*" modules="iisnode"/>
    </handlers>
    <rewrite>
      <rules>
        <rule name="StaticContent">
          <action type="Rewrite" url="public{REQUEST_URI}"/>
        </rule>
        <rule name="DynamicContent">
          <conditions>
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="True"/>
          </conditions>
          <action type="Rewrite" url="index.js"/>
        </rule>
      </rules>
    </rewrite>
    <security>
      <requestFiltering removeServerHeader="true" />
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
EOF

# Create a deployment package
echo "Creating deployment package..."
zip -r site.zip .

# Deploy the application
echo "Deploying application to $APP_SERVICE..."
az webapp deployment source config-zip \
    --name $APP_SERVICE \
    --resource-group $RESOURCE_GROUP \
    --src site.zip

# Clean up
cd -
rm -rf $DEPLOY_DIR

echo "=== Deployment completed successfully ==="
echo "Application should be available at: https://$APP_SERVICE.azurewebsites.net" 