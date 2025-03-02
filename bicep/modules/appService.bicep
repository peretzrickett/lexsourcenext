// modules/appService.bicep

@description('Name of the client for the App Service')
param clientName string

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Subnet ID for VNet integration to enable private network access (FrontEnd subnet)')
param subnetId string

@description('ID of the App Service Plan to associate with this App Service')
param appServicePlanId string

@description('Tags to apply to the App Service for organization and billing')
param tags object = {}

@description('Environment variables (App Settings) for configuring the App Service')
param appSettings array = []

// Create the App Service resource
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: 'app-${discriminator}-${clientName}'
  location: resourceGroup().location  
  properties: {
    serverFarmId: appServicePlanId
    publicNetworkAccess: 'Enabled'

    siteConfig: {
      vnetRouteAllEnabled: true // Ensure all outbound traffic follows VNet routes for security
      scmIpSecurityRestrictionsUseMain: true // Apply IP restrictions to the SCM (Kudu) site, matching main site
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
          vnetSubnetResourceId: subnetId // Allow traffic only from the FrontEnd subnet
          description: 'Allow traffic from the FrontEnd subnet for secure access'
        }
        {
          name: 'DenyPublic'
          priority: 200
          action: 'Deny'
          ipAddress: '0.0.0.0/0' // Block all public traffic for enhanced security
          description: 'Deny all public internet access'
        }
      ]
    }

    httpsOnly: true  // Enforce HTTPS for secure communication
  }
  tags: tags
}

// Enforce VNet integration with FrontEnd subnet (where Microsoft.Web/serverFarms delegation exists)
// This ensures the App Service can access resources in the VNet securely via the delegated subnet
resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2022-03-01' = {
  name: 'virtualNetwork'
  parent: appService
  properties: {
    subnetResourceId: subnetId  // Integrate App Service with the FrontEnd subnet in the spoke VNet
  }
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
        vnetSubnetResourceId: subnetId  // Restrict access to only FrontEnd VNet traffic for security
        description: 'Allow traffic only from the FrontEnd VNet for enhanced isolation'
      }
    ]
  }
  dependsOn: [vnetIntegration]
}

@description('The resource ID of the deployed App Service')
output id string = appService.id

@description('The default URL of the App Service')
output defaultHostName string = appService.properties.defaultHostName

@description('The name of the App Service for reference')
output name string = appService.name
