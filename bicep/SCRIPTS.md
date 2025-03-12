# Bicep Deployment Script Documentation

This document provides an overview of shell scripts used for managing Azure deployments in this project.

> **Note**: As new scripts are added or existing scripts are modified, please update this document to maintain accurate documentation. This ensures all team members have current information about script usage and capabilities.

## Discriminator Parameter

> **IMPORTANT**: All scripts now accept a `discriminator` parameter that is essential for consistent resource naming and management across environments. The discriminator is used as part of resource group and resource naming conventions.

- **What is the discriminator?** A short string (typically 4-5 characters) that uniquely identifies an environment or deployment (e.g., "lexsb", "lexwa", "prod", "dev")
- **Why is it necessary?** It enables multiple parallel deployments in the same subscription without naming conflicts
- **Default value:** Most scripts use "lexsb" as the default if no discriminator is provided
- **Usage example:** `./script_name.sh myenv` where "myenv" is your discriminator value

Resource group naming pattern: `rg-{discriminator}-{purpose}` (e.g., `rg-lexsb-central`, `rg-lexsb-clienta`)

## Core Deployment Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `go.sh` | Main deployment script | `./go.sh [discriminator]` | - Validates bicep template and parameters<br>- Offers to run what-if deployment simulation<br>- Deploys the templates to Azure<br>- Monitors deployment status<br>- Saves deployment logs |
| `clean-all.sh` | Complete resource cleanup | `./clean-all.sh [discriminator]` | - Deletes resource groups for each client with the specified discriminator<br>- Deletes the central resource group<br>- **Use with caution** - removes all infrastructure |
| `clean-deployments.sh` | Clean failed deployments | `./clean-deployments.sh [discriminator]` | - Lists and deletes failed deployments in resource groups with the specified discriminator<br>- Doesn't affect successfully deployed resources<br>- Useful after deployment failures |
| `cancel-all-deployments.sh` | Cancel running deployments | `./cancel-all-deployments.sh` | - Cancels all in-progress deployments<br>- Works at both subscription and resource group levels<br>- Useful for stopping stuck deployments |

## Utility Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `bicep-join.sh` | Combine bicep files | `./bicep-join.sh` | - Concatenates all bicep files into `all_bicep.txt`<br>- Useful for searching across templates |
| `inspect-rgs.sh` | List resource groups | `./inspect-rgs.sh [discriminator]` | - Shows all related resource groups with the specified discriminator<br>- Provides overview of deployed infrastructure |
| `zone-cleanup.sh` | Remove DNS zones | `./zone-cleanup.sh [discriminator]` | - Specifically targets private DNS zones in resource groups with the specified discriminator<br>- Removes DNS zone links first, then zones<br>- Useful for DNS-related deployment issues |
| `reset-cloud.sh` | Reset with preservation | `./reset-cloud.sh [discriminator]` | - Preserves key components (vaults, storage, identities)<br>- Removes other resources with the specified discriminator<br>- Useful for partial redeployment |

## VPN-Related Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `deploy-vpn.sh` | VPN-only deployment | `./deploy-vpn.sh [discriminator]` | - Deploys only VPN-related resources with the specified discriminator<br>- Creates certificates and managed identity<br>- Can be used independently from main infrastructure |
| `generate-vpn-certs.sh` | Create VPN certificates | `./generate-vpn-certs.sh [discriminator]` | - Generates certificates for VPN authentication<br>- Stores them in Azure Key Vault<br>- Used by the VPN gateway for client authentication |
| `get-vpn-cert.sh` | Retrieve VPN certificates | `./get-vpn-cert.sh [discriminator]` | - Downloads VPN client certificates from Key Vault with the specified discriminator<br>- Formats certificates for VPN client configuration<br>- Useful when setting up new VPN clients |

## Front Door and App Deployment Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `deploy-frontdoor-clientb.sh` | Deploy Front Door for ClientB | `./deploy-frontdoor-clientb.sh [discriminator]` | - Creates Azure Front Door components for ClientB with the specified discriminator<br>- Sets up origin group, origin, endpoint, and route |
| `deploy-testapp-ClientB.sh` | Deploy test app to ClientB | `./deploy-testapp-ClientB.sh [discriminator]` | - Deploys a test web application to ClientB with the specified discriminator<br>- Creates resources if they don't exist<br>- Configures app settings |
| `simple-testapp.sh` | Deploy simple app to ClientB | `./simple-testapp.sh [discriminator]` | - Deploys a simple application to ClientB using GitHub source with the specified discriminator |
| `basic-testapp.sh` | Deploy basic HTML app | `./basic-testapp.sh [discriminator]` | - Deploys a basic HTML page to ClientB with the specified discriminator |

## Validation Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `validate-deployment.sh` | Validate deployment | `./validate-deployment.sh [discriminator]` | - Checks DNS configurations with the specified discriminator<br>- Validates Front Door routing<br>- Tests network connectivity<br>- Verifies private endpoint connections<br>- Confirms firewall rules are working |
| `test-afd-script.sh` | Test Front Door configuration | `./test-afd-script.sh [discriminator]` | - Tests Azure Front Door configuration with the specified discriminator<br>- Creates test origin group |

## Best Practices

1. **Always provide a discriminator** when running scripts to ensure consistent naming across your deployment:
   ```
   ./script_name.sh myenv
   ```

2. Always run validation before deployment: 
   ```
   az deployment sub validate --location eastus --template-file main.bicep --parameters @clients.json discriminator=myenv
   ```

3. Use what-if deployment to preview changes: 
   ```
   az deployment sub what-if --location eastus --template-file main.bicep --parameters @clients.json discriminator=myenv
   ```

4. After failed deployments, run `clean-deployments.sh` with your discriminator to clear failed deployment operations:
   ```
   ./clean-deployments.sh myenv
   ```

5. For complete reset, use `clean-all.sh` with your discriminator (be cautious as this removes all resources):
   ```
   ./clean-all.sh myenv
   ```

6. When making DNS zone changes, use `zone-cleanup.sh` with your discriminator to remove DNS zones before redeployment:
   ```
   ./zone-cleanup.sh myenv
   ```

## Troubleshooting Common Issues

| Issue | Resolution Script | Notes |
|-------|-----------------|-------|
| Failed deployments | `clean-deployments.sh [discriminator]` | Clears stuck deployment operations |
| DNS resolution problems | `zone-cleanup.sh [discriminator]` | Removes and allows recreation of private DNS zones |
| VPN client connectivity | `get-vpn-cert.sh [discriminator]` | Ensures proper VPN certificate configuration |
| Network connectivity | `validate-deployment.sh [discriminator]` | Tests connectivity across the environment |
| Complete environment reset | `clean-all.sh [discriminator]` | Use with caution - completely removes all deployed resources |