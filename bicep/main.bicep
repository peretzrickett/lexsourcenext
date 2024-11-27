param location string = 'eastus'

module vnet 'modules/vnet.bicep' = {
  name: 'vnetDeployment'
  params: {
    name: 'myVNet'
    location: location
    addressPrefixes: ['10.0.0.0/16']
    subnets: [
      { name: 'FrontEnd'; addressPrefix: '10.0.1.0/24' }
      { name: 'BackEnd'; addressPrefix: '10.0.2.0/24' }
      { name: 'CICD'; addressPrefix: '10.0.3.0/24' }
    ]
  }
}

module appServicePlan 'modules/appServicePlan.bicep' = {
  name: 'appServicePlanDeployment'
  params: {
    name: 'myAppServicePlan'
    location: location
    sku: {
      name: 'P1v2'
      tier: 'PremiumV2'
      size: '1'
    }
  }
}

module appService 'modules/appService.bicep' = {
  name: 'appServiceDeployment'
  params: {
    name: 'myAppService'
    location: location
    appServicePlanId: appServicePlan.outputs.id
  }
}

module sqlServer 'modules/sqlServer.bicep' = {
  name: 'sqlServerDeployment'
  params: {
    name: 'my-sql-server'
    location: location
    adminLogin: 'adminUser'
    adminPassword: 'Password@123!'
  }
}

module privateEndpoint 'modules/privateEndpoint.bicep' = {
  name: 'privateEndpointDeployment'
  params: {
    name: 'sqlPrivateEndpoint'
    location: location
    subnetId: vnet.outputs.subnets[1].id
    privateLinkServiceId: sqlServer.outputs.id
    groupIds: ['sqlServer']
  }
}

module firewall 'modules/firewall.bicep' = {
  name: 'firewallDeployment'
  params: {
    name: 'myFirewall'
    location: location
    vnetId: vnet.outputs.id
  }
}
