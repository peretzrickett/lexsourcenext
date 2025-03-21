# Architecture Overview

This document provides an overview of the infrastructure architecture deployed by this project. The system uses Azure Front Door for global traffic management and private connectivity to backend App Services.

## Resource Naming with Discriminator Pattern

> **IMPORTANT:** This architecture uses a discriminator pattern for all resource naming to enable multiple parallel deployments in the same subscription without naming conflicts.

- **What is a discriminator?** A short string (typically 4-5 characters) that uniquely identifies an environment or deployment instance
- **Why is it necessary?** It allows multiple versions of the infrastructure to coexist in a single subscription
- **How is it used?** The discriminator is incorporated into all resource group and resource names
- **Default value:** If not specified, most scripts use "lexsb" as the default discriminator

### Naming Patterns

- Resource Groups: `rg-{discriminator}-{purpose}` (e.g., `rg-lexsb-central`, `rg-lexsb-clienta`)
- App Services: `app-{discriminator}-{client}` (e.g., `app-lexsb-ClientA`)
- Front Door Components: `afd-{component}-{discriminator}-{client}` (e.g., `afd-ep-lexsb-ClientA`)
- Virtual Networks: `vnet-{discriminator}-{client}` (e.g., `vnet-lexsb-central`)
- Key Vaults: `kv-{discriminator}-{client}` (e.g., `kv-lexsb-central`)

All commands and operations must use a consistent discriminator to target the correct resources.

## Infrastructure Diagram

```
                                         Internet
                                            |
                                            v
                                +-------------------------+
                                |      Azure Front Door   |
                                |     (globalFrontDoor)   |
                                +-------------------------+
                                  /                     \
                                 /                       \
+----------------------------------+               +----------------------------------+
| Origin Group: afd-og-lexsb-ClientA |             | Origin Group: afd-og-lexsb-ClientB |
+----------------------------------+               +----------------------------------+
                |                                               |
                v                                               v
+----------------------------------+               +----------------------------------+
| Endpoint: afd-ep-lexsb-ClientA   |               | Endpoint: afd-ep-lexsb-ClientB   |
+----------------------------------+               +----------------------------------+
                |                                               |
                v                                               v
+----------------------------------+               +----------------------------------+
| Route: afd-rt-lexsb-ClientA      |               | Route: afd-rt-lexsb-ClientB      |
+----------------------------------+               +----------------------------------+
                |                                               |
                v                                               v
+----------------------------------+               +----------------------------------+
| Origin: afd-o-lexsb-ClientA      |               | Origin: afd-o-lexsb-ClientB      |
+----------------------------------+               +----------------------------------+
                |                                               |
                | Private Link                                  | Private Link
                v                                               v
+----------------------------------+               +----------------------------------+
| Resource Group: rg-lexsb-ClientA |               | Resource Group: rg-lexsb-ClientB |
|                                  |               |                                  |
| +------------------------------+ |               | +------------------------------+ |
| | App Service                  | |               | | App Service                  | |
| | (app-lexsb-ClientA)          | |               | | (app-lexsb-ClientB)          | |
| +------------------------------+ |               | +------------------------------+ |
|                                  |               |                                  |
| +------------------------------+ |               | +------------------------------+ |
| | Virtual Network              | |               | | Virtual Network              | |
| +------------------------------+ |               | +------------------------------+ |
|                                  |               |                                  |
| +------------------------------+ |               | +------------------------------+ |
| | Network Security Group       | |               | | Network Security Group       | |
| +------------------------------+ |               | +------------------------------+ |
|                                  |               |                                  |
| +------------------------------+ |               | +------------------------------+ |
| | Private Endpoint             | |               | | Private Endpoint             | |
| +------------------------------+ |               | +------------------------------+ |
+----------------------------------+               +----------------------------------+

                          |
                          | Resource Group: rg-lexsb-central
          +---------------+----------------+
          |                                |
+--------------+    +--------------+    +--------------+
|   Key Vault   |    | User Assigned|    | Private DNS  |
|               |    |  Identity    |    |    Zones     |
+--------------+    +--------------+    +--------------+
```

The above diagram shows the infrastructure with a discriminator of "lexsb". When working with a different environment, replace "lexsb" with your discriminator.

## Component Overview

### Global Resources

- **Azure Front Door (globalFrontDoor)**: Acts as a global entry point that routes traffic to the appropriate backend services based on URL path, hostname, or other criteria. Provides CDN capabilities, WAF protection, and route traffic to private backends.

### Central Resources (Resource Group: rg-{discriminator}-central)

- **Key Vault**: Securely stores secrets, certificates, and keys used in the deployment
- **User Assigned Identity**: Used by deployment scripts to access and configure Azure resources
- **Private DNS Zones**: Manages DNS resolution for private endpoints
- **Front Door Components**:
  - **Origin Groups**: Logical groupings of origins for load balancing
  - **Origins**: Backend services with private link connections to App Services
  - **Endpoints**: Externally accessible endpoints that clients connect to
  - **Routes**: Rules that map requests to the appropriate origins

### Client Resources (Per Client)

- **App Service**: Hosts the web application for each client
- **Virtual Network**: Provides network isolation for each client's resources
- **Network Security Group**: Controls inbound and outbound traffic to the client resources
- **Private Endpoint**: Enables private connectivity from Front Door to App Services

## Private Connectivity Flow

1. End users access the application through Azure Front Door
2. Front Door routes requests to the appropriate origin group and origin
3. Traffic flows from Front Door to the App Service through a Private Link connection
4. The App Service is isolated in a virtual network and not directly exposed to the internet
5. Network Security Groups filter traffic to allow only Azure Front Door to access the App Service

## Deployment Script Workflow

The deployment process follows these steps:

1. Deploy central resources (Key Vault, User Identity, etc.) with specified discriminator
2. Deploy client-specific resources in separate resource groups with the same discriminator
3. Deploy Azure Front Door profile
4. Deploy origin groups, origins, endpoints, and routes for each client
5. Configure private link connections between Front Door and App Services
6. Approve private link connections to establish private connectivity

All deployment commands and scripts require the discriminator parameter to ensure consistent naming across the environment:

```bash
./script_name.sh myenv
```

## Security Considerations

- All backend services are isolated in virtual networks
- Traffic between Front Door and backends uses private links, not traversing the public internet
- Network Security Groups restrict access to only authorized services
- Key sensitive resources are protected with proper RBAC permissions
- Public access to App Services can be disabled once private connectivity is established

## Managing Multiple Environments

With the discriminator pattern, you can deploy multiple parallel environments in the same subscription:

1. Development environment: `./go.sh dev`
2. Testing environment: `./go.sh test`
3. Production environment: `./go.sh prod`

Each environment will have its own resource groups and resources with the discriminator incorporated into their names, allowing them to coexist without conflicts. 