# Discriminator Pattern for Resource Naming

## Overview

The discriminator pattern is a naming convention used throughout this project to enable multiple parallel deployments of the same infrastructure in a single Azure subscription. This document explains the purpose, implementation, and best practices for using the discriminator pattern.

## What is a Discriminator?

A discriminator is a short string (typically 4-5 characters) that uniquely identifies an environment or deployment instance. Examples include:

- `lexsb` - Default environment
- `lexwa` - Secondary environment
- `dev` - Development environment
- `test` - Testing environment
- `prod` - Production environment

## Why is a Discriminator Necessary?

A discriminator is essential for several reasons:

1. **Uniqueness**: Azure requires globally unique names for many resources like storage accounts, app services, and key vaults
2. **Parallel Deployments**: Enables multiple copies of the infrastructure to coexist in the same subscription
3. **Environment Segregation**: Clearly separates resources belonging to different environments
4. **Consistent Naming**: Provides a systematic approach to resource naming across the infrastructure
5. **Script Targeting**: Allows operational scripts to target specific environments based on the discriminator

## Implementation

### Resource Naming Patterns

All resources follow consistent naming patterns that incorporate the discriminator:

- **Resource Groups**: `rg-{discriminator}-{purpose}`
  - Example: `rg-lexsb-central`, `rg-lexsb-clienta`

- **App Services**: `app-{discriminator}-{client}`
  - Example: `app-lexsb-ClientA`

- **Storage Accounts**: `stg{discriminator}{client}`
  - Example: `stglexsbclienta` (lowercase, no hyphens due to storage account naming restrictions)

- **Key Vaults**: `kv-{discriminator}-{client}`
  - Example: `kv-lexsb-central`

- **Virtual Networks**: `vnet-{discriminator}-{purpose}`
  - Example: `vnet-lexsb-central`

- **Front Door Components**:
  - Origin Groups: `afd-og-{discriminator}-{client}`
  - Origins: `afd-o-{discriminator}-{client}`
  - Endpoints: `afd-ep-{discriminator}-{client}`
  - Routes: `afd-rt-{discriminator}-{client}`

### Script Parameterization

All scripts have been updated to accept a discriminator as a parameter:

```bash
# Syntax
./script_name.sh [discriminator]

# Examples
./go.sh lexsb                  # Deploy with 'lexsb' discriminator
./clean-all.sh dev             # Clean resources with 'dev' discriminator
./validate-deployment.sh prod  # Validate 'prod' environment
```

If not specified, scripts use a default discriminator (typically "lexsb").

### Bicep Template Parameters

The Bicep templates accept a `discriminator` parameter that is propagated to all resource definitions:

```bicep
@description('Discriminator used in resource naming for multi-instance deployments')
param discriminator string = 'lexsb'

// Example resource definition
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: 'stg${discriminator}${client}'
  // ...
}
```

## Best Practices

1. **Consistency**: Always use the same discriminator for related resources
2. **Documentation**: Document which discriminators are used for which environments
3. **Brevity**: Keep discriminators short (4-5 characters) due to name length limits
4. **Distinctiveness**: Use clearly different discriminators to avoid confusion
5. **Default Value**: Provide sensible defaults in scripts for convenience
6. **Explicit Usage**: Always specify the discriminator in commands for clarity:
   ```bash
   az deployment sub what-if --location eastus --template-file main.bicep --parameters discriminator=myenv @clients.json
   ```

## Common Pitfalls

1. **Mixed Discriminators**: Using different discriminators for related resources will break connectivity
2. **Name Length Limits**: Some Azure resources have strict name length limits (e.g., storage accounts: 24 characters)
3. **Character Restrictions**: Some resources prohibit hyphens or require lowercase (adjust pattern accordingly)
4. **Forgetting the Discriminator**: Operations on existing resources will fail if the discriminator is omitted
5. **Default Overrides**: Be careful when scripts have different default discriminators

## Managing Multiple Environments

The discriminator pattern allows managing multiple parallel environments:

| Environment | Discriminator | Resource Group Examples |
|-------------|---------------|------------------------|
| Default     | `lexsb`       | `rg-lexsb-central`, `rg-lexsb-clienta` |
| Development | `dev`         | `rg-dev-central`, `rg-dev-clienta` |
| Testing     | `test`        | `rg-test-central`, `rg-test-clienta` |
| Production  | `prod`        | `rg-prod-central`, `rg-prod-clienta` |

## Cleanup Considerations

When cleaning up resources, always specify the correct discriminator to avoid accidentally removing resources from other environments:

```bash
# Clean only resources with 'dev' discriminator
./clean-all.sh dev

# Inspect resource groups with 'test' discriminator
./inspect-rgs.sh test
```

## Conclusion

The discriminator pattern is essential for maintaining order and enabling multiple deployments of the infrastructure in a single subscription. Always specify the discriminator in all operations to ensure you're targeting the correct resources. 