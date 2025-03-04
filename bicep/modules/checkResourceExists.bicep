@description('The type of resource to check existence for (e.g. Microsoft.Network/virtualNetworkGateways)')
param resourceType string

@description('The name of the resource to check')
param resourceName string

// For simplicity, initially assume the resource doesn't exist
// We'll use this approach to avoid dependency on deployment scripts
// which can cause issues during multi-resource deployments

@description('Whether the resource exists - default to false to safely create resources')
output exists bool = false