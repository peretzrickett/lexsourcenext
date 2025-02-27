// modules/frontDoorConfigure.bicep

@description('Name of the Azure Front Door instance')
param name string

@description('Names of the clients to create Front Door resources for')
param clientNames array

@description('Distinguished qualifier for resources')
param discriminator string

// Deployment Script to Configure AFD Components (Fixed Environment Variables)
resource configureAFD 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'configure-frontend-${name}'
  location: 'eastus'
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${resourceId('rg-central', 'Microsoft.ManagedIdentity/userAssignedIdentities', 'uami-deployment-scripts')}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    scriptContent: '''
      #!/bin/bash
      set -ex

      RESOURCE_GROUP="$RESOURCE_GROUP"
      FRONTDOOR_NAME="$FRONTDOOR_NAME"
      DISCRIMINATOR="$DISCRIMINATOR"
      
      IFS=',' read -r -a CLIENT_NAMES <<< "$CLIENT_NAMES"

      az config set extension.use_dynamic_install=yes_without_prompt

      for CLIENT in "${CLIENT_NAMES[@]}"; do
          ORIGIN_GROUP="afd-og-${DISCRIMINATOR}-${CLIENT}"
          ORIGIN_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
          ENDPOINT_NAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
          ROUTE_NAME="afd-rt-${DISCRIMINATOR}-${CLIENT}"
          ORIGIN_HOST="app-${DISCRIMINATOR}-${CLIENT}.privatelink.azurewebsites.net"

          az afd origin-group create --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONTDOOR_NAME" --origin-group-name "$ORIGIN_GROUP" \
            --probe-request-type GET --probe-protocol Https \
            --probe-interval-in-seconds 30 --sample-size 4 \
            --successful-samples-required 3 --probe-path "/" \
            --additional-latency-in-milliseconds 50

          az afd origin create --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONTDOOR_NAME" --origin-group-name "$ORIGIN_GROUP" \
            --origin-name "$ORIGIN_NAME" --host-name "$ORIGIN_HOST" \
            --origin-host-header "$ORIGIN_HOST" --http-port 80 --https-port 443 \
            --priority 1 --weight 1000 --enabled-state Enabled \
            --enforce-certificate-name-check false

          az afd endpoint create --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONTDOOR_NAME" --endpoint-name "$ENDPOINT_NAME" \
            --enabled-state Enabled

          az afd route create --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONTDOOR_NAME" --endpoint-name "$ENDPOINT_NAME" \
            --route-name "$ROUTE_NAME" --origin-group "$ORIGIN_GROUP" \
            --supported-protocols Https --forwarding-protocol HttpsOnly \
            --link-to-default-domain Enabled --https-redirect Disabled
      done
    '''
    environmentVariables: [
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'FRONTDOOR_NAME', value: name }
      { name: 'DISCRIMINATOR', value: discriminator }
      { name: 'CLIENT_NAMES', value: join(clientNames, ',') }
    ]
    retentionInterval: 'PT1H'
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
  }
}
