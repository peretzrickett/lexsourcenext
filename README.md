# Azure Multi-Tenant Infrastructure Deployment

This project uses Azure Bicep to deploy a secure, multi-tenant infrastructure with private networking, Front Door, and VPN connectivity. The deployment creates a hub-and-spoke network architecture with central shared services and isolated client environments.

## Documentation

- [**SCRIPTS.md**](/bicep/SCRIPTS.md) - Detailed guide to all shell scripts
- [**Bicep Modules**](#core-modules-and-execution-order) - Overview of bicep modules and execution order
- [**VPN.md**](/bicep/VPN.md) - VPN setup and client configuration *(coming soon)*
- [**DEPLOYMENT.md**](/bicep/DEPLOYMENT.md) - Detailed deployment walkthrough *(coming soon)*

## Architecture Overview

The architecture follows these key principles:

- **Hub and Spoke Network**: Central hub VNet with connected client VNets
- **Private Endpoints**: All Azure services use private endpoints
- **Front Door**: Azure Front Door for global traffic management
- **Private DNS Integration**: Centralized private DNS zones for all services
- **VPN Connectivity**: Point-to-site VPN for secure access

## Directory Structure

```
/bicep/
├── main.bicep                 # Main deployment entry point
├── clients.json               # Client configuration parameters
├── modules/                   # Modular bicep components
│   ├── centralResources.bicep # Hub resources deployment
│   ├── clientResources.bicep  # Spoke resources for each client
│   ├── vpn.bicep              # VPN gateway configuration
│   └── ...                    # Other resource-specific modules
├── *.sh                       # Deployment and utility scripts
└── SCRIPTS.md                 # Documentation for shell scripts
```

## Core Modules and Execution Order

| Module | Purpose | Execution Order | Dependencies |
|--------|---------|-----------------|--------------|
| `resourceGroup.bicep` | Creates resource groups | 1 | None |
| `managedIdentity.bicep` | Identity for deployment scripts | 2 | Resource groups |
| `centralResources.bicep` | Hub network and services | 3 | Resource groups |
| `clientResources.bicep` | Spoke networks and services | 3 | Resource groups |
| `privateDnsZone.bicep` | Private DNS zones | 4 | Central and client resources |
| `vnetPeering.bicep` | Hub-spoke connectivity | 5 | DNS zones, central and client VNets |
| `frontDoorConfigure.bicep` | Global traffic manager | 6 | VNet peering |
| `vpn.bicep` | VPN gateway | 7 | Front Door, central resources |

## Key Parameters

- **clients**: Array defining each client environment (name, network CIDR, subnet configuration)
- **discriminator**: Unique qualifier for resource naming
- **location**: Azure region for deployment
- **deployVpn**: Flag to enable/disable VPN deployment

## Deployment Instructions

### Quick Start

1. **Prerequisites**: 
   - Azure CLI installed and authenticated (`az login`)
   - Bicep CLI installed (`az bicep install`)
   - Subscription set and permissions confirmed

2. **Configure**: Edit `clients.json` with your environment definitions

3. **Deploy**:
   ```bash
   cd bicep
   ./go.sh
   ```

4. **Verify**: Run `./validate-deployment.sh` after deployment completes

For detailed deployment instructions, see the [Deployment Guide](#detailed-deployment) below.

---

## <a name="detailed-deployment"></a>Detailed Deployment Guide

### Prerequisites

1. **Azure CLI**: Ensure Azure CLI is installed and you're logged in
   ```bash
   az login
   ```

2. **Bicep CLI**: Install the Bicep CLI
   ```bash
   az bicep install
   ```

3. **Subscription**: Set your active subscription
   ```bash
   az account set --subscription <subscription-id>
   ```

4. **Permissions**: Ensure you have Owner or Contributor rights on the target subscription

### Configuration

1. **Client Configuration**: Edit `clients.json` to define your environments
   ```json
   [
     {
       "name": "ClientA",
       "cidr": "10.1.0.0/16",
       "subnets": {
         "frontEnd": "10.1.1.0/24",
         "backEnd": "10.1.2.0/24",
         "privateLink": "10.1.3.0/24"
       }
     },
     ...
   ]
   ```

2. **Parameter Adjustments**: Modify parameters in `main.bicep` if needed
   - Change `discriminator` for unique naming
   - Adjust `location` for your target region

### Deployment Process

1. **Validate Templates**:
   ```bash
   az deployment sub validate --location eastus --template-file bicep/main.bicep --parameters @bicep/clients.json
   ```

2. **Preview Changes**:
   ```bash
   az deployment sub what-if --location eastus --template-file bicep/main.bicep --parameters @bicep/clients.json
   ```

3. **Deploy Infrastructure**:
   ```bash
   cd bicep
   ./go.sh
   ```

4. **Monitor Deployment**:
   - The go.sh script will track deployment progress
   - Use Azure Portal or CLI to view detailed status

### Post-Deployment

1. **Validate Connectivity**:
   ```bash
   cd bicep
   ./validate-deployment.sh
   ```

2. **VPN Configuration**:
   - Download the VPN client package from the Azure Portal
   - Import the VPN certificate from Key Vault
   - Configure client VPN settings

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Failed deployments | Run `./clean-deployments.sh` to clear deployments, then retry |
| DNS resolution issues | Run `./zone-cleanup.sh` to remove DNS zones, then redeploy |
| Front Door routing problems | Use `./test-frontdoor.sh` to test Front Door configuration |
| Stuck deployments | Run `./cancel-all-deployments.sh` to cancel all running deployments |
| Complete reset | Run `./clean-all.sh` to remove all deployed resources (use with caution) |
| VPN issues | Try the standalone VPN deployment: `./deploy-vpn.sh` |

## Contributing

When extending this deployment:

1. Use separate modules for new resource types
2. Follow naming conventions in the existing code
3. Add dependency handling for proper deployment order
4. Test with validation and what-if before actual deployment
5. **Documentation Updates**: 
   - Document new modules in README.md module reference
   - Add any new scripts to SCRIPTS.md
   - Maintain VPN.md for VPN-related changes
   - Keep DEPLOYMENT.md current with deployment process changes
   - Ensure all documentation stays in sync with code changes

## Security Considerations

- All services use private endpoints
- Network Security Groups restrict traffic
- Key Vault stores sensitive configuration
- VPN provides secure access to resources
- Private DNS prevents public resolution
- Front Door WAF can be enabled for protection

## Maintenance

Regular maintenance tasks:

1. Keep Azure CLI and Bicep CLI updated
2. Review NSG rules and security configurations
3. Check for expired certificates
4. Verify backup configurations
5. Monitor resource utilization

## Additional Resources

- [Azure Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Private Link Documentation](https://learn.microsoft.com/en-us/azure/private-link/)
- [Azure VPN Gateway](https://learn.microsoft.com/en-us/azure/vpn-gateway/)
- [Azure Front Door](https://learn.microsoft.com/en-us/azure/frontdoor/)