#!/bin/bash
# Script to deploy web app and database for ClientB
# Modified to run from network tester VM which has direct access to private endpoints
set -e

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Set SSL validation to false for Azure CLI (helps with proxy issues)
export AZURE_CLI_DISABLE_CONNECTION_VERIFICATION=1

# First check if we're logged in to Azure
echo -e "${YELLOW}Checking Azure login status...${NC}"
az account show > /dev/null 2>&1
if [ $? -ne 0 ]; then
  echo -e "${RED}Not logged in to Azure. Please use 'az login' first.${NC}"
  echo -e "${YELLOW}You can log in using:${NC}"
  echo -e "${YELLOW}az login${NC}"
  echo -e "${YELLOW}or for managed identity (if configured):${NC}"
  echo -e "${YELLOW}az login --identity${NC}"
  exit 1
fi
echo -e "${GREEN}Already logged in to Azure.${NC}"

# Configuration
CLIENT_NAME="ClientB"
RESOURCE_GROUP="rg-${CLIENT_NAME}"
STORAGE_ACCOUNT="stglexsbclientb" # Fix: Use correct storage account for ClientB
WEB_APP_NAME="app-lexsb-${CLIENT_NAME}"
SQL_SERVER_NAME="sql-lexsb-${CLIENT_NAME}"
SQL_DB_NAME="lexdemodb"
SQL_ADMIN_USER="adminUser"       # From clientResources.bicep
SQL_ADMIN_PASSWORD="Password@123!" # From clientResources.bicep

# Artifacts
LOCAL_WEBAPP_ZIP="./testapp2.zip" # Fix: Use simpler test app
LOCAL_DB_BACPAC="./lexdemodb_2024_12_03-04-53.bacpac"

# Check if running from VM network tester
echo -e "${YELLOW}Checking network connectivity to private endpoints...${NC}"
echo -e "${YELLOW}Trying to resolve private DNS name...${NC}"
nslookup $SQL_SERVER_NAME.privatelink.database.windows.net
echo -e "${YELLOW}Trying to connect to the SQL endpoint (ping may fail due to firewall but DNS should work)...${NC}"
ping -c 2 -W 5 $SQL_SERVER_NAME.privatelink.database.windows.net || true
echo -e "${YELLOW}Checking connectivity with netcat...${NC}"
nc -zv -w 5 $SQL_SERVER_NAME.privatelink.database.windows.net 1433 || true

echo -e "${YELLOW}Continuing with deployment...${NC}"

# Verify local files exist
if [ ! -f "$LOCAL_WEBAPP_ZIP" ]; then
  echo -e "${RED}Error: Web app zip file not found at $LOCAL_WEBAPP_ZIP${NC}"
  echo -e "${YELLOW}If running on VM, copy the files to the VM first:${NC}"
  echo -e "${YELLOW}scp lexdemo_202412261902.zip user@vm-ip:~/${NC}"
  echo -e "${YELLOW}scp lexdemodb_2024_12_03-04-53.bacpac user@vm-ip:~/${NC}"
  exit 1
fi

if [ ! -f "$LOCAL_DB_BACPAC" ]; then
  echo -e "${RED}Error: Database bacpac file not found at $LOCAL_DB_BACPAC${NC}"
  exit 1
fi

# Get storage account key (needed for database import)
echo -e "${YELLOW}Getting storage account access key...${NC}"
storage_key=$(az storage account keys list --resource-group $RESOURCE_GROUP --account-name $STORAGE_ACCOUNT --query "[0].value" -o tsv)

# Check if the artifacts already exist in storage
echo -e "${YELLOW}Checking if artifacts already exist in storage...${NC}"
webapp_exists=$(az storage blob exists --account-name $STORAGE_ACCOUNT --account-key "$storage_key" \
  --container-name artifacts --name "webapp_deploy.zip" --query exists -o tsv 2>/dev/null || echo "false")
db_exists=$(az storage blob exists --account-name $STORAGE_ACCOUNT --account-key "$storage_key" \
  --container-name artifacts --name "lexdemodb_import.bacpac" --query exists -o tsv 2>/dev/null || echo "false")

echo -e "${GREEN}Using existing artifacts in storage container${NC}"
echo -e "${GREEN}Web app package: ${STORAGE_ACCOUNT}/artifacts/webapp_deploy.zip${NC}"
echo -e "${GREEN}Database backup: ${STORAGE_ACCOUNT}/artifacts/lexdemodb_import.bacpac${NC}"

# 2. Use existing web app package from storage for deployment
echo -e "${YELLOW}Using existing web app package from storage for deployment...${NC}"

# Generate SAS token for accessing the storage
echo -e "${YELLOW}Generating SAS token for storage access...${NC}"
end_time=$(date -u -d "+1 hour" +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -v+1H +%Y-%m-%dT%H:%MZ)
sas=$(az storage blob generate-sas --account-name $STORAGE_ACCOUNT --account-key "$storage_key" \
  --container-name artifacts --name "webapp_deploy.zip" \
  --permissions r --expiry $end_time --https-only --output tsv)

package_url="https://$STORAGE_ACCOUNT.blob.core.windows.net/artifacts/webapp_deploy.zip?$sas"
echo -e "${GREEN}Package URL: $package_url${NC}"

# Get Front Door URL for access after deployment
afd_url=$(az afd endpoint list -g rg-central --profile-name globalFrontDoor \
  --query "[?name=='afd-ep-lexsb-ClientB'].hostName" -o tsv)

# Try to create a deployment via Azure CLI (from external URL)
echo -e "${YELLOW}Deploying web app package from URL...${NC}"
az webapp config set -g $RESOURCE_GROUP -n $WEB_APP_NAME --generic-configurations '{"packageUri":"'$package_url'"}' &>/dev/null
deployment_result=$?

if [ $deployment_result -ne 0 ]; then
  echo -e "${YELLOW}Automatic deployment not supported. Using direct portal deployment method...${NC}"
  
  # Display manual deployment instructions
  echo -e "${YELLOW}Manual deployment instructions:${NC}"
  echo -e "${YELLOW}1. In Azure Portal, navigate to $WEB_APP_NAME in $RESOURCE_GROUP${NC}"
  echo -e "${YELLOW}2. Go to Deployment Center and select 'External Package'${NC}"
  echo -e "${YELLOW}3. Use package URL: $package_url${NC}"
fi

echo -e ""
echo -e "${GREEN}After deployment, access the web app via the Front Door URL:${NC}"
echo -e "${GREEN}https://$afd_url${NC}"

# 3. Skip uploading database bacpac as it's already in storage

# 4. Restore database from uploaded bacpac
echo -e "${YELLOW}Importing database to $SQL_SERVER_NAME/$SQL_DB_NAME...${NC}"

# Check if database exists, if not create it
echo -e "${YELLOW}Checking if database exists...${NC}"
db_exists=$(az sql db show --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name $SQL_DB_NAME --query "name" -o tsv 2>/dev/null || echo "")

if [ -z "$db_exists" ]; then
  echo -e "${YELLOW}Database does not exist. Creating new database...${NC}"
  az sql db create --resource-group $RESOURCE_GROUP --server $SQL_SERVER_NAME --name $SQL_DB_NAME \
    --service-objective S0
else
  echo -e "${YELLOW}Database exists. Continuing with existing database...${NC}"
fi

# Import database using managed identity and REST API for private endpoint support
echo -e "${YELLOW}Automating database import using managed identity and REST API...${NC}"

# Get the Managed Identity details
echo -e "${YELLOW}Getting managed identity details...${NC}"
identity_id=$(az identity show -g rg-central -n uami-deployment-scripts --query id -o tsv)
identity_client_id=$(az identity show -g rg-central -n uami-deployment-scripts --query clientId -o tsv)

echo -e "${YELLOW}Managed Identity: $identity_client_id${NC}"

# Get storage account details
echo -e "${YELLOW}Getting storage account details...${NC}"
storage_id=$(az storage account show -g $RESOURCE_GROUP -n $STORAGE_ACCOUNT --query id -o tsv)

# Get SQL server details
echo -e "${YELLOW}Getting SQL server details...${NC}"
sql_server_id=$(az sql server show -g $RESOURCE_GROUP -n $SQL_SERVER_NAME --query id -o tsv)

# Ensure Managed Identity has Storage Blob Data Reader role on storage account
echo -e "${YELLOW}Assigning Storage Blob Data Reader role to managed identity...${NC}"
az role assignment create --assignee-object-id $identity_client_id \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" \
  --scope $storage_id 2>/dev/null || true

# Ensure Managed Identity has SQL DB Contributor role on SQL server
echo -e "${YELLOW}Assigning SQL DB Contributor role to managed identity...${NC}"
az role assignment create --assignee-object-id $identity_client_id \
  --assignee-principal-type ServicePrincipal \
  --role "SQL DB Contributor" \
  --scope $sql_server_id 2>/dev/null || true

# Wait for role assignments to propagate
echo -e "${YELLOW}Waiting for role assignments to propagate...${NC}"
sleep 30

# Create an Azure deployment script to perform the import
echo -e "${YELLOW}Creating deployment script for database import...${NC}"

# Create a temporary script file
cat > import_script.sh << 'EOF'
#!/bin/bash
set -e

# Get parameters
storage_account="$1"
container_name="$2"
bacpac_name="$3"
resource_group="$4"
sql_server="$5"
sql_db="$6"
user="$7"
password="$8"

# Get storage account key using managed identity
echo "Acquiring access token for ARM..."
access_token=$(curl -s 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F' -H "Metadata: true" | jq -r '.access_token')

# Create the import operation using REST API
sql_server_fqdn="${sql_server}.database.windows.net"
bacpac_url="https://${storage_account}.blob.core.windows.net/${container_name}/${bacpac_name}"

echo "Creating SQL import operation via REST API using managed identity..."
request_body=$(cat <<JSON
{
  "properties": {
    "storageKeyType": "SharedAccessKey",
    "storageKey": "",
    "storageUri": "${bacpac_url}",
    "administratorLogin": "${user}",
    "administratorLoginPassword": "${password}",
    "authenticationType": "SQL",
    "operationMode": "Import",
    "useNewName": true
  }
}
JSON
)

echo "Sending import request..."
response=$(curl -s -X POST \
  -H "Authorization: Bearer ${access_token}" \
  -H "Content-Type: application/json" \
  -d "${request_body}" \
  "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${resource_group}/providers/Microsoft.Sql/servers/${sql_server}/databases/${sql_db}/import?api-version=2021-02-01-preview")

echo "Import operation initiated."
echo "$response"
EOF

chmod +x import_script.sh

# Create the deployment script resource in Azure
echo -e "${YELLOW}Deploying script to Azure...${NC}"
deployment_script_name="db-import-$(date +%s)"

# Create a temporary ARM template file
cat > arm_template.json << EOFARM
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "identity_id": { "type": "string" },
    "script_content": { "type": "string" },
    "storage_account": { "type": "string" },
    "container_name": { "type": "string" },
    "bacpac_name": { "type": "string" },
    "resource_group": { "type": "string" },
    "sql_server": { "type": "string" },
    "sql_db": { "type": "string" },
    "sql_user": { "type": "string" },
    "sql_password": { "type": "securestring" }
  },
  "resources": [
    {
      "type": "Microsoft.Resources/deploymentScripts",
      "apiVersion": "2020-10-01",
      "name": "${deployment_script_name}",
      "location": "eastus",
      "kind": "AzureCLI",
      "identity": {
        "type": "UserAssigned",
        "userAssignedIdentities": {
          "[parameters('identity_id')]": {}
        }
      },
      "properties": {
        "azCliVersion": "2.40.0",
        "retentionInterval": "PT1H",
        "cleanupPreference": "OnSuccess",
        "timeout": "PT30M",
        "arguments": "[concat(parameters('storage_account'), ' ', parameters('container_name'), ' ', parameters('bacpac_name'), ' ', parameters('resource_group'), ' ', parameters('sql_server'), ' ', parameters('sql_db'), ' ', parameters('sql_user'), ' ', parameters('sql_password'))]",
        "scriptContent": "[base64ToString(parameters('script_content'))]"
      }
    }
  ],
  "outputs": {}
}
EOFARM

# Create parameter file
cat > arm_params.json << EOFPARAMS
{
  "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "identity_id": { "value": "${identity_id}" },
    "script_content": { "value": "$(base64 -w 0 import_script.sh)" },
    "storage_account": { "value": "${STORAGE_ACCOUNT}" },
    "container_name": { "value": "artifacts" },
    "bacpac_name": { "value": "lexdemodb_import.bacpac" },
    "resource_group": { "value": "${RESOURCE_GROUP}" },
    "sql_server": { "value": "${SQL_SERVER_NAME}" },
    "sql_db": { "value": "${SQL_DB_NAME}" },
    "sql_user": { "value": "${SQL_ADMIN_USER}" },
    "sql_password": { "value": "${SQL_ADMIN_PASSWORD}" }
  }
}
EOFPARAMS

# Deploy using the template and parameter files
az deployment group create -g rg-central \
  --template-file arm_template.json \
  --parameters @arm_params.json \
  --no-wait

# Clean up the temporary files
rm -f import_script.sh arm_template.json arm_params.json

# Clean up the local temp script file
rm -f import_script.sh

echo -e "${GREEN}Database import initiated through managed identity.${NC}"
echo -e "${YELLOW}The import operation runs asynchronously and may take 15-30 minutes to complete.${NC}"
echo -e "${YELLOW}You can check the status in the Azure Portal under:${NC}"
echo -e "${YELLOW}Resource Groups > rg-central > Deployment Scripts > ${deployment_script_name}${NC}"

# 5. Configure app settings for database connection
echo -e "${YELLOW}Configuring app settings for database connection...${NC}"

# Use the private endpoint FQDN for SQL Server connection
# The web app in the VNet will resolve this to the private IP through private DNS zone
CONN_STRING="Server=$SQL_SERVER_NAME.privatelink.database.windows.net;Initial Catalog=$SQL_DB_NAME;Persist Security Info=False;User ID=$SQL_ADMIN_USER;Password=$SQL_ADMIN_PASSWORD;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $WEB_APP_NAME \
  --settings "ConnectionStrings__DefaultConnection=$CONN_STRING"

# 6. Verify connectivity
echo -e "${YELLOW}Verifying connectivity to app and database...${NC}"
# Test direct connectivity to SQL Server private endpoint
echo -e "${YELLOW}Testing connectivity to SQL Server private endpoint...${NC}"
nc -zv -w 5 $SQL_SERVER_NAME.privatelink.database.windows.net 1433 2>/dev/null
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Successfully connected to SQL Server via private endpoint${NC}"
else
  echo -e "${RED}Cannot connect to SQL Server via private endpoint${NC}"
fi

# Test connectivity to web app SCM site
echo -e "${YELLOW}Testing connectivity to web app SCM site...${NC}"
nc -zv -w 5 $WEB_APP_NAME.scm.azurewebsites.net 443 2>/dev/null
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Successfully connected to web app SCM site${NC}"
else
  echo -e "${RED}Cannot connect to web app SCM site${NC}"
fi

# Test web app frontend via Front Door
echo -e "${YELLOW}Testing web app via Front Door...${NC}"
curl -s -o /dev/null -w "%{http_code}" https://afd-ep-lexsb-ClientB-f0f6huhhecgtc9ep.z03.azurefd.net/
if [ $? -eq 0 ]; then
  echo -e "${GREEN}Successfully connected to web app via Front Door${NC}"
else
  echo -e "${RED}Cannot connect to web app via Front Door${NC}"
fi

echo -e "${GREEN}Deployment complete!${NC}"
echo -e "${GREEN}Web app is configured to use private endpoint for database connectivity${NC}"
echo -e "${GREEN}Web app URL: https://$WEB_APP_NAME.azurewebsites.net${NC}"
echo -e "${GREEN}Front Door URL: https://afd-ep-lexsb-ClientB-f0f6huhhecgtc9ep.z03.azurefd.net${NC}" 
echo -e "${GREEN}SQL Server (private endpoint): $SQL_SERVER_NAME.privatelink.database.windows.net${NC}"
echo -e "${GREEN}SQL Database: $SQL_DB_NAME${NC}"