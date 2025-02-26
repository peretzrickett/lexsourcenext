// modules/appService.bicep
@description('Location where the App Service will be deployed')
param location string

@description('Name of the client')
param clientName string

@description('Distinguished qualifier for resources')
param discriminator string

@description('Subnet ID for Private Link')
param subnetId string

@description('ID of the App Service Plan')
param appServicePlanId string

@description('Tags to apply to the App Service')
param tags object = {}

@description('Environment variables (App Settings) for the App Service')
param appSettings array = []

// Create the App Service resource with public access disabled
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: 'app-${discriminator}-${clientName}'
  location: location
  properties: {
    serverFarmId: appServicePlanId
    publicNetworkAccess: 'Disabled' // Disable public access

    siteConfig: {
      vnetRouteAllEnabled: true // Ensure all outbound traffic follows VNet routes
      scmIpSecurityRestrictionsUseMain: true // Apply restrictions to the SCM (Kudu) site
      appSettings: [
        for setting in appSettings: {
          name: setting.name
          value: setting.value
        }
      ]
      ipSecurityRestrictions: [
        {
          name: 'AllowPrivateSubnet'
          priority: 100
          action: 'Allow'
          vnetSubnetResourceId: subnetId // Ensure Private Link subnet is allowed
        }
        {
          name: 'DenyPublic'
          priority: 200
          action: 'Deny'
          ipAddress: '0.0.0.0/0' // Block all public traffic
        }
      ]
    }

    httpsOnly: true  // Enforce HTTPS
  }
  tags: tags
}

// Enforce VNet integration with Private Endpoint
resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2022-03-01' = {
  name: 'virtualNetwork'
  parent: appService
  properties: {
    subnetResourceId: subnetId  // Integrate App Service with the specified VNet
  }
  dependsOn: [appService]
}

resource appServiceRestrictions 'Microsoft.Web/sites/config@2022-03-01' = {
  name: 'web'
  parent: appService
  properties: {
    ipSecurityRestrictions: [
      {
        name: 'AllowVNetOnly'
        action: 'Allow'
        priority: 100
        vnetSubnetResourceId: subnetId  // Only allow VNet traffic
        description: 'Allow only VNet traffic'
      }
    ]
  }
  dependsOn: [vnetIntegration]
}


// Private Endpoint for App Service
module privateEndpoint 'privateEndpoint.bicep' = {
  name: 'pe-${appService.name}'
  params: {
    name: 'pe-${appService.name}'
    clientName: clientName
    discriminator: discriminator
    location: location
    privateLinkServiceId: appService.id
    privateDnsZoneName: 'privatelink.azurewebsites.net'
    groupId: 'sites'
    serviceType: 'AppService'
    tags: tags
  }
}

// Output the resource ID of the App Service
@description('The resource ID of the App Service')
output id string = appService.id

// Output the default URL of the App Service
@description('The default URL of the App Service')
output defaultHostName string = appService.properties.defaultHostName

// Output the name of the App Service
@description('The name of the App Service')
output name string = appService.name
