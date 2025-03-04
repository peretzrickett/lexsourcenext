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

@description('Enable public network access for debugging purposes')
param enablePublicAccess bool = false

@description('CIDR block for the Azure Front Door managed private endpoints')
param afdManagedEndpointsCidr string = '10.8.0.0/16'

// Create the App Service resource
resource appService 'Microsoft.Web/sites@2022-03-01' = {
  name: 'app-${discriminator}-${clientName}'
  location: resourceGroup().location  
  properties: {
    serverFarmId: appServicePlanId
    publicNetworkAccess: enablePublicAccess ? 'Enabled' : 'Disabled'

    siteConfig: {
      vnetRouteAllEnabled: true // Ensure all outbound traffic follows VNet routes for security
      scmIpSecurityRestrictionsUseMain: true // Apply IP restrictions to the SCM (Kudu) site, matching main site
      alwaysOn: true // Keep the app always running for better performance
      minTlsVersion: '1.2' // Enforce TLS 1.2 minimum for security
      appSettings: [
        for setting in appSettings: {
          name: setting.name
          value: setting.value
        }
        // Add settings for VNet integration
        {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        }
        {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16' // Azure DNS server for private DNS resolution
        }
      ]
      ipSecurityRestrictions: [
        {
          name: 'AllowVNetSubnet'
          priority: 100
          action: 'Allow'
          vnetSubnetResourceId: subnetId // Allow traffic from the FrontEnd subnet
          description: 'Allow traffic from the FrontEnd subnet for secure access'
        }
        {
          name: 'AllowFrontDoorEndpoints'
          priority: 110
          action: 'Allow'
          ipAddress: afdManagedEndpointsCidr
          description: 'Allow traffic from Azure Front Door managed private endpoints'
        }
        {
          name: 'AllowFrontDoorService'
          priority: 120
          action: 'Allow'
          ipAddress: 'AzureFrontDoor.Backend'
          tag: 'ServiceTag'
          description: 'Allow traffic from Azure Front Door service'
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
    swiftSupported: true
  }
}

@description('The resource ID of the deployed App Service')
output id string = appService.id

@description('The default URL of the App Service')
output defaultHostName string = appService.properties.defaultHostName

@description('The name of the App Service for reference')
output name string = appService.name

@description('The outbound IP addresses of the App Service')
output outboundIpAddresses array = split(appService.properties.outboundIpAddresses, ',')
