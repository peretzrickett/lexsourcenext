@description('ID of the Private Endpoint')
param privateEndpointId string

@description('Name of the Private Endpoint')
param name string

@description('Timeout for the script execution in seconds')
param timeout int = 30

@description('Client name')
param clientName string

@description('Discriminator')
param discriminator string

var subscriptionId = split(privateEndpointId, '/')[2]

// Extract Resource Group from Private Endpoint ID
// var resourceGroupName = split(privateEndpointId, '/')[4]

// Extract Discriminator & Client Name
// Assumes Private Endpoint name follows format: 'pe-{service}-{discriminator}-{clientName}'
// var peName = last(split(privateEndpointId, '/'))
// var discriminator = split(peName, '-')[2]
// var clientName = split(peName, '-')[3]

// // Construct Storage Account Name
// var storageAccountName = 'stg${discriminator}${clientName}'

// // Extract NIC Name from Private Endpoint
// var nicNameScript = 'az network private-endpoint show --ids ${privateEndpointId} --query "networkInterfaces[0].id" --output tsv | awk -F\'/\' \'{print $NF}\''

// // Extract IP Configuration Name from NIC
// var ipConfigNameScript = 'az network nic show --name $(az network private-endpoint show --ids ${privateEndpointId} --query "networkInterfaces[0].id" --output tsv | awk -F\'/\' \'{print $NF}\') --resource-group ${resourceGroupName} --query "ipConfigurations[0].name" --output tsv'

// // Extract Private IP Address
// var privateIpScript = 'az network nic show --name $(az network private-endpoint show --ids ${privateEndpointId} --query "networkInterfaces[0].id" --output tsv | awk -F\'/\' \'{print $NF}\') --resource-group ${resourceGroupName} --query "ipConfigurations[0].properties.privateIPAddress" --output tsv'

// // Reference the existing User Assigned Managed Identity
// resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
//   name: 'uami-deployment-scripts'
//   scope: resourceGroup('rg-central') // Update if the UAMI is in a different resource group
// }

// Deploy the script that retrieves the Private IP
resource privateIpRetrieval 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'extract-private-ip-${name}'
  kind: 'AzureCLI'
  location: resourceGroup().location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      # Read arguments
      SUBSCRIPTION_ID=$1
      PRIVATE_ENDPOINT_ID=$2

      # Set the subscription
      az account set --subscription "$SUBSCRIPTION_ID"

      # Retrieve Private IP from Private Endpoint
      PRIVATE_IP=$(az network private-endpoint show --ids "$PRIVATE_ENDPOINT_ID" --query "networkInterfaces[0].ipConfigurations[0].privateIPAddress" -o tsv)

      # Error handling
      if [ -z "$PRIVATE_IP" ]; then
        echo "Error: Private IP not found"
        exit 1
      fi

      # Output Private IP
      echo "Private IP: $PRIVATE_IP"
      echo "$PRIVATE_IP" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    arguments: '${subscriptionId} ${privateEndpointId}'
    timeout: 'PT60S'
    retentionInterval: 'P1D'
  }
}



// Output the retrieved Private IP Address
output privateIp string = privateIpRetrieval.properties.outputs.privateIp
