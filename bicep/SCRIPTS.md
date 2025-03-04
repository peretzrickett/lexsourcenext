# Bicep Deployment Script Documentation

This document provides an overview of shell scripts used for managing Azure deployments in this project.

> **Note**: As new scripts are added or existing scripts are modified, please update this document to maintain accurate documentation. This ensures all team members have current information about script usage and capabilities.

## Core Deployment Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `go.sh` | Main deployment script | `./go.sh` | - Validates bicep template and parameters<br>- Offers to run what-if deployment simulation<br>- Deploys the templates to Azure<br>- Monitors deployment status<br>- Saves deployment logs |
| `clean-all.sh` | Complete resource cleanup | `./clean-all.sh` | - Deletes resource groups for each client<br>- Deletes the central resource group<br>- **Use with caution** - removes all infrastructure |
| `clean-deployments.sh` | Clean failed deployments | `./clean-deployments.sh` | - Lists and deletes failed deployments<br>- Doesn't affect successfully deployed resources<br>- Useful after deployment failures |
| `cancel-all-deployments.sh` | Cancel running deployments | `./cancel-all-deployments.sh` | - Cancels all in-progress deployments<br>- Works at both subscription and resource group levels<br>- Useful for stopping stuck deployments |

## Utility Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `bicep-join.sh` | Combine bicep files | `./bicep-join.sh` | - Concatenates all bicep files into `all_bicep.txt`<br>- Useful for searching across templates |
| `inspect-rgs.sh` | List resource groups | `./inspect-rgs.sh` | - Shows all related resource groups<br>- Provides overview of deployed infrastructure |
| `zone-cleanup.sh` | Remove DNS zones | `./zone-cleanup.sh` | - Specifically targets private DNS zones<br>- Removes DNS zone links first, then zones<br>- Useful for DNS-related deployment issues |

## VPN-Specific Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `deploy-vpn.sh` | VPN-only deployment | `./deploy-vpn.sh` | - Deploys only VPN-related resources<br>- Creates certificates and managed identity<br>- Can be used independently from main infrastructure |

## Specialized/Optional Scripts

| Script | Purpose | Usage | Description |
|--------|---------|-------|-------------|
| `test-frontdoor.sh` | Test Front Door | `./test-frontdoor.sh` | - Focuses on Front Door resources<br>- Troubleshoots Front Door configuration |
| `validate-deployment.sh` | Validate deployment | `./validate-deployment.sh` | - Checks DNS configurations<br>- Validates Front Door routing<br>- Tests network connectivity |
| `reset-cloud.sh` | Reset with preservation | `./reset-cloud.sh` | - Preserves key components (vaults, storage, identities)<br>- Removes other resources<br>- Useful for partial redeployment |

## Best Practices

1. Always run validation before deployment: 
   ```
   az deployment sub validate --location eastus --template-file main.bicep --parameters @clients.json
   ```

2. Use what-if deployment to preview changes: 
   ```
   az deployment sub what-if --location eastus --template-file main.bicep --parameters @clients.json
   ```

3. After failed deployments, run `clean-deployments.sh` to clear failed deployment operations

4. For complete reset, use `clean-all.sh` (be cautious as this removes all resources)

5. When making DNS zone changes, use `zone-cleanup.sh` to remove DNS zones before redeployment