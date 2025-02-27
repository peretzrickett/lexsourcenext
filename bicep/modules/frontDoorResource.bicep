// @description('Name of the Azure Front Door instance')
// param name string

// @description('Names of the clients to create Front Door resources for')
// param clientNames array

// @description('Distinguished qualifier for resources')
// param discriminator string

// @description('SKU tier for the Azure Front Door')
// @allowed([
//   'Premium_AzureFrontDoor'
// ])
// param skuTier string = 'Premium_AzureFrontDoor'

// @description('Tags to apply to the Azure Front Door instance')
// param tags object = {}

// resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
//   name: name
//   location: 'global'
//   sku: {
//     name: skuTier
//   }
//   properties: {
//     originResponseTimeoutSeconds: 60
//   }
//   tags: tags
// }

// // Ensure the Front Door profile exists and is fully provisioned before creating origin groups
// @batchSize(1)
// resource afdBackendPools 'Microsoft.Cdn/profiles/afdOriginGroups@2024-02-01' = [for (clientName, index) in clientNames: {
//   name: 'afd-og-${discriminator}-${clientName}'
//   parent: frontDoor
//   properties: {
//     sessionAffinityEnabledState: 'Disabled'
//     loadBalancingSettings: {
//       sampleSize: 4
//       successfulSamplesRequired: 3
//     }
//     healthProbeSettings: {
//       probePath: '/' // Adjust if App Service requires a specific health endpoint
//       probeProtocol: 'Https'
//       probeIntervalInSeconds: 30
//     }
//     provisioningState: 'Succeeded' // Explicitly set to ensure origin group creation
//   }
//   dependsOn: [
//     frontDoor
//   ]
// }]

// // Create Origins (App Services) for each client, using privatelink
// @batchSize(1)
// resource afdOrigins 'Microsoft.Cdn/profiles/afdOriginGroups/origins@2024-02-01' = [for (clientName, index) in clientNames: {
//   name: 'afd-o-${discriminator}-${clientName}'
//   parent: afdBackendPools[index]
//   properties: {
//     hostName: 'app-${discriminator}-${clientName}.privatelink.azurewebsites.net'  // Private DNS name
//     originHostHeader: 'app-${discriminator}-${clientName}.privatelink.azurewebsites.net'
//     httpPort: 80
//     httpsPort: 443
//     enabledState: 'Enabled'
//     priority: 1
//     weight: 1000
//     privateLinkResource: {
//       id: resourceId('Microsoft.Web/sites', 'app-${discriminator}-${clientName}') // Points to App Service
//     }
//     privateLinkLocation: 'eastus' // Adjust based on your region
//     enforceCertificateNameCheck: false
//   }
//   dependsOn: [
//     frontDoor
//     afdBackendPools[index] // Ensure backend pools exist
//   ]
// }]

// // Create Frontend Endpoints for each client
// @batchSize(1)
// resource afdFrontend 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = [for (clientName, index) in clientNames: {
//   name: 'afd-ep-${discriminator}-${clientName}'
//   location: 'global'
//   parent: frontDoor
//   properties: {
//     enabledState: 'Enabled'
//     // Removed 'hostName' as it's read-only; Azure Front Door assigns a default hostname
//   }
//   dependsOn: [
//     frontDoor
//     afdBackendPools[index] // Added dependency on origin groups to ensure they exist
//   ]
// }]

// // Create Routing Rules for each client
// @batchSize(1)
// resource afdRoutingRules 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = [for (clientName, index) in clientNames: {
//   name: 'afd-rt-${discriminator}-${clientName}'
//   parent: afdFrontend[index]
//   properties: {
//     supportedProtocols: [
//       'Https'
//     ]
//     patternsToMatch: [
//       '/*' // Catch-all pattern for testing, adjust as needed
//     ]
//     originGroup: {
//       id: afdBackendPools[index].id
//     }
//     forwardingProtocol: 'HttpsOnly'
//     cacheConfiguration: {
//       queryStringCachingBehavior: 'IgnoreQueryString'
//       compressionSettings: {
//         isCompressionEnabled: true
//       }
//     }
//     ruleSets: [
//       {
//         id: resourceId('Microsoft.Cdn/profiles/ruleSets', name, 'DefaultRuleSet')
//       }
//     ]
//     enabledState: 'Enabled'
//   }
//   dependsOn: [
//     afdBackendPools[index]
//     afdFrontend[index]
//     afdOrigins[index]
//   ]
// }]

// @description('The resource ID of the Azure Front Door instance')
// output id string = frontDoor.id

// @description('The name of the Azure Front Door instance')
// output name string = frontDoor.name
