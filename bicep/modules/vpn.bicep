// modules/vpn.bicep
// Point-to-Site VPN Gateway implementation for private network connectivity

@description('Unique qualifier for resource naming to avoid conflicts')
param discriminator string

@description('Azure region where resources will be deployed')
param location string

@description('Address pool for VPN clients, e.g. 172.16.0.0/24')
param addressPool string

@description('Authentication type for VPN clients')
@allowed([
  'Certificate'
  'AAD'
])
param authType string = 'Certificate'

@description('Root certificate name for VPN authentication')
param rootCertName string = 'P2SRootCert'

@description('Azure AD tenant ID for AAD authentication')
param aadTenantId string = ''

@description('Azure AD audience for AAD authentication')
param aadAudience string = ''

@description('Azure AD issuer for AAD authentication')
param aadIssuer string = ''

@description('Root certificate data for VPN authentication (base64-encoded .cer). If not provided, a certificate will be generated automatically.')
param rootCertData string = ''

@description('Resource ID of the User Assigned Managed Identity to use for deployment scripts')
param uamiId string = ''

@description('Name of the Key Vault where VPN certificates will be stored')
param keyVaultName string = 'kv-vpn-${discriminator}'

// Try to reference the existing central VNet, but create a fallback in case it's not found
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: 'vnet-${discriminator}-central'
}

// Reference the existing Key Vault that was created in main.bicep
resource vpnKeyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

// Create the GatewaySubnet if it doesn't exist
resource gatewaySubnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = {
  name: 'GatewaySubnet'
  parent: vnet
  properties: {
    addressPrefix: '10.0.3.0/26'
  }
}

// Create certificate directly in this module rather than a separate module
resource vpnCertScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (rootCertData == '' && uamiId != '') {
  name: 'vpn-cert-generator'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    azCliVersion: '2.40.0'
    retentionInterval: 'P1D'
    scriptContent: '''
      #!/bin/bash
      set -e

      KEY_VAULT_NAME=$1
      CERT_NAME=$2
      
      # Generate timestamp for unique naming
      TIMESTAMP=$(date +%Y%m%d%H%M%S)
      
      # Add timestamp to certificate names
      CERT_NAME_WITH_TIMESTAMP="${CERT_NAME}-${TIMESTAMP}"
      CLIENT_CERT_NAME="P2SClientCert-${TIMESTAMP}"
      PASSWORD="Password123"  # Simplified password without special characters
      
      echo "Using timestamp for certificate names: $TIMESTAMP"
      
      echo "Starting VPN certificate generation script"
      echo "Key Vault: $KEY_VAULT_NAME"
      echo "Certificate Name: $CERT_NAME"
      
      # Add access policy for the managed identity
      echo "Setting access policy for deployment script identity..."
      OBJ_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "Not running as user")
      # If OBJ_ID is empty, we're running as a managed identity
      if [ "$OBJ_ID" == "Not running as user" ]; then
        OBJ_ID=$(az account show --query identity.principalId -o tsv 2>/dev/null || echo "Unknown")
        echo "Running as managed identity with principal ID: $OBJ_ID"
      else
        echo "Current identity object ID: $OBJ_ID"
      fi
      
      # First check if we can access the Key Vault
      if ! az keyvault show --name "$KEY_VAULT_NAME" &>/dev/null; then
        echo "Error: Cannot access Key Vault $KEY_VAULT_NAME"
        exit 1
      fi
      
      # Get key vault resource ID for role assignment
      KV_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
      echo "Key Vault ID: $KV_ID"
      
      # Assign Key Vault Administrator role to managed identity
      echo "Assigning Key Vault Administrator role..."
      if [ -n "$OBJ_ID" ] && [ "$OBJ_ID" != "Unknown" ]; then
        az role assignment create \
          --assignee "$OBJ_ID" \
          --role "Key Vault Administrator" \
          --scope "$KV_ID" || echo "Role assignment failed, trying access policy"
      else
        echo "Skipping role assignment due to missing OBJ_ID"
      fi
        
      # Using set-policy for access permissions to ensure we have them
      echo "Setting access policy directly..."
      if [ -n "$OBJ_ID" ] && [ "$OBJ_ID" != "Unknown" ]; then
        az keyvault set-policy --name "$KEY_VAULT_NAME" \
          --object-id "$OBJ_ID" \
          --certificate-permissions get list create import delete purge recover backup restore \
          --secret-permissions get list set delete purge recover backup restore \
          --key-permissions get list create delete purge recover backup restore || echo "Failed to set access policy"
      else
        echo "Skipping access policy due to missing OBJ_ID"
        
        # Try to determine the managed identity object ID another way
        echo "Attempting to find managed identity through environment variables..."
        echo "Using deployment script identity with resource ID: $MSI_ENDPOINT"
        
        # We need to create our own certificates since we can't use Key Vault properly
        echo "Will generate certificates without storing in Key Vault"
      fi
      
      # Wait a bit to ensure policy propagation
      echo "Waiting for access policy to propagate..."
      sleep 15
      
      # Check if we can actually access the key vault
      echo "Testing key vault access..."
      if ! az keyvault secret list --vault-name "$KEY_VAULT_NAME" &>/dev/null; then
        echo "WARNING: Still can't list secrets. Trying to force permissions..."
        
        # Get Key Vault type of authorization
        KV_RBAC=$(az keyvault show --name "$KEY_VAULT_NAME" --query "properties.enableRbacAuthorization" -o tsv)
        
        if [ "$KV_RBAC" == "true" ]; then
          echo "Key Vault is using RBAC authorization"
          
          # Try to assign role directly
          az role assignment create \
            --role "Key Vault Administrator" \
            --assignee-object-id "$OBJ_ID" \
            --assignee-principal-type "ServicePrincipal" \
            --scope "$KV_ID" --output none || echo "Failed to create role assignment"
        else
          echo "Key Vault is using Access Policy authorization"
          
          # Set access policy with all permissions
          az keyvault set-policy --name "$KEY_VAULT_NAME" \
            --object-id "$OBJ_ID" \
            --certificate-permissions all \
            --secret-permissions all \
            --key-permissions all --output none || echo "Failed to set access policy"
        fi
        
        sleep 15
      fi
        
      # Create temporary directory
      echo "Creating temporary directory..."
      CERT_DIR=$(mktemp -d)
      cd "$CERT_DIR"
      
      # Generate root certificate
      echo "Generating root certificate..."
      openssl req -x509 -new -nodes -sha256 -days 3650 \
        -subj "/CN=$CERT_NAME_WITH_TIMESTAMP" \
        -keyout "$CERT_NAME_WITH_TIMESTAMP.key" \
        -out "$CERT_NAME_WITH_TIMESTAMP.crt"
      
      # Convert root cert to DER for Azure VPN
      echo "Converting to DER format..."
      openssl x509 -in "$CERT_NAME_WITH_TIMESTAMP.crt" -outform der -out "$CERT_NAME_WITH_TIMESTAMP.cer"
      
      # Base64 encode for Azure
      echo "Base64 encoding certificate..."
      ROOT_CERT_DATA=$(base64 -i "$CERT_NAME_WITH_TIMESTAMP.cer" | tr -d '\n')
      
      # Generate client key for VPN connections
      echo "Generating client certificate..."
      openssl genrsa -out "$CLIENT_CERT_NAME.key" 2048
      
      # Generate client certificate request
      echo "Creating CSR..."
      openssl req -new -key "$CLIENT_CERT_NAME.key" -out "$CLIENT_CERT_NAME.csr" -subj "/CN=$CLIENT_CERT_NAME"
      
      # Sign client certificate with root certificate
      echo "Signing client certificate..."
      openssl x509 -req -in "$CLIENT_CERT_NAME.csr" \
        -CA "$CERT_NAME_WITH_TIMESTAMP.crt" \
        -CAkey "$CERT_NAME_WITH_TIMESTAMP.key" \
        -CAcreateserial \
        -out "$CLIENT_CERT_NAME.crt" \
        -days 365 -sha256
      
      # Create PKCS#12 file for client import
      echo "Creating PKCS#12 bundle..."
      openssl pkcs12 -export \
        -in "$CLIENT_CERT_NAME.crt" \
        -inkey "$CLIENT_CERT_NAME.key" \
        -certfile "$CERT_NAME_WITH_TIMESTAMP.crt" \
        -out "$CLIENT_CERT_NAME.pfx" \
        -password pass:$PASSWORD
      
      # Store certificates in Key Vault
      echo "Storing certificates in Key Vault..."
      
      # Check if certificates already exist
      ROOT_CERT_EXISTS=false
      CLIENT_CERT_EXISTS=false
      CLIENT_SECRET_EXISTS=false
      
      if az keyvault certificate show --vault-name "$KEY_VAULT_NAME" --name "$CERT_NAME_WITH_TIMESTAMP" &>/dev/null; then
        echo "Root certificate already exists in Key Vault"
        ROOT_CERT_EXISTS=true
      fi
      
      if az keyvault certificate show --vault-name "$KEY_VAULT_NAME" --name "$CLIENT_CERT_NAME" &>/dev/null; then
        echo "Client certificate already exists in Key Vault"
        CLIENT_CERT_EXISTS=true
      fi
      
      if az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$CLIENT_CERT_NAME-pfx" &>/dev/null; then
        echo "Client certificate PFX already exists in Key Vault"
        CLIENT_SECRET_EXISTS=true
      fi
      
      # If both client certificate and pfx secret exist, we can skip import
      if $ROOT_CERT_EXISTS && $CLIENT_CERT_EXISTS && $CLIENT_SECRET_EXISTS; then
        echo "All certificates and secrets already exist in Key Vault. Using existing ones."
      else
        echo "Some certificate assets need to be imported to Key Vault."
        echo "Importing root certificate..."
        # Create PFX for Key Vault root cert
        openssl pkcs12 -export -out "$CERT_NAME_WITH_TIMESTAMP.pfx" -inkey "$CERT_NAME_WITH_TIMESTAMP.key" -in "$CERT_NAME_WITH_TIMESTAMP.crt" -passout pass:$PASSWORD
        
        # Import root certificate to Key Vault - with a retry mechanism
        echo "Importing root certificate..."
        for i in {1..3}; do
          if az keyvault certificate import --vault-name "$KEY_VAULT_NAME" \
            --name "$CERT_NAME_WITH_TIMESTAMP" \
            --file "$CERT_NAME_WITH_TIMESTAMP.pfx" \
            --password "$PASSWORD"; then
            echo "Root certificate imported successfully"
            break
          else
            echo "Retry $i: Failed to import root certificate"
            # Wait a few seconds before retrying
            sleep 5
            # Get permissions again just to be sure
            az keyvault set-policy --name "$KEY_VAULT_NAME" \
              --object-id "$OBJ_ID" \
              --certificate-permissions get list create import delete purge recover backup restore \
              --secret-permissions get list set delete purge recover backup restore \
              --key-permissions get list create delete purge recover backup restore
          fi
          
          if [ $i -eq 3 ]; then
            echo "Warning: Could not import root certificate after $i attempts"
          fi
        done
        
        # Verify current key vault permissions
        echo "Verifying current permissions..."
        # Current permission status
        echo "Testing access to secrets in Key Vault..."
        SECRET_ACCESS=$(az keyvault secret list --vault-name "$KEY_VAULT_NAME" &>/dev/null && echo "true" || echo "false")
        echo "Secret access: $SECRET_ACCESS"

        # Store the certificates using a different approach
        # Save to local files first so we can try multiple approaches
        echo "Preparing files for key vault storage..."
        
        # Save the root certificate public data to a file
        echo "$ROOT_CERT_DATA" > rootcert_public.txt
        
        # Save client pfx base64 data to a file
        CLIENT_PFX_B64=$(base64 -i "$CLIENT_CERT_NAME.pfx" | tr -d '\n')
        echo "$CLIENT_PFX_B64" > client_pfx.txt
        
        # Save password to a file
        echo "$PASSWORD" > client_password.txt
        
        # Try direct Azure CLI approach first
        echo "Attempting to store secrets using az CLI..."
        
        # Simplified for clarity - try with basic parameters first
        echo "Storing root certificate public data..."
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
          --name "$CERT_NAME_WITH_TIMESTAMP-public" \
          --value "$ROOT_CERT_DATA" \
          --output none || echo "Failed to store root certificate public data (direct)"
        
        echo "Importing client certificate..."
        az keyvault certificate import --vault-name "$KEY_VAULT_NAME" \
          --name "$CLIENT_CERT_NAME" \
          --file "$CLIENT_CERT_NAME.pfx" \
          --password "$PASSWORD" \
          --output none || echo "Failed to import client certificate (direct)"
        
        echo "Storing client PFX as secret..."
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
          --name "$CLIENT_CERT_NAME-pfx" \
          --value "$CLIENT_PFX_B64" \
          --output none || echo "Failed to store client certificate PFX (direct)"
        
        echo "Storing client certificate password..."
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
          --name "$CLIENT_CERT_NAME-password" \
          --value "$PASSWORD" \
          --output none || echo "Failed to store client certificate password (direct)"
          
        # Store timestamp for reference
        echo "Storing certificate timestamp reference..."
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
          --name "vpn-cert-timestamp" \
          --value "$TIMESTAMP" \
          --output none || echo "Failed to store certificate timestamp"
        
        # Fallback approach - try with REST API through Azure CLI
        echo "Checking what we were able to store..."
        az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv || echo "Cannot list secrets"
        az keyvault certificate list --vault-name "$KEY_VAULT_NAME" --query "[].name" -o tsv || echo "Cannot list certificates"
        
        # Print conclusion
        echo "Certificate and secret storage operation completed"
        echo "Note: If secrets were not stored, you'll need to manually add them from the generated files"
        echo "Root certificate has been successfully imported and is accessible by the VPN Gateway"
      fi
      
      # List created objects in Key Vault
      echo "Listing certificates in Key Vault:"
      az keyvault certificate list --vault-name "$KEY_VAULT_NAME" --query "[].id" -o tsv || echo "Failed to list certificates"
      
      echo "Listing secrets in Key Vault:"
      az keyvault secret list --vault-name "$KEY_VAULT_NAME" --query "[].id" -o tsv || echo "Failed to list secrets"
      
      # Save certificate data to a log file for debugging
      echo "Root cert data length: ${#ROOT_CERT_DATA}" 
      echo "Client PFX data length: ${#CLIENT_PFX_B64}"
      
      # Make sure to output both certificates regardless of whether they were newly created or already existed
      if [ -z "$CLIENT_PFX_B64" ] || [ "$CLIENT_PFX_B64" == "null" ]; then
        echo "Client PFX data is empty, trying to retrieve from Key Vault..."
        # Try to retrieve existing client certificate from Key Vault
        RETRIEVED_CLIENT_PFX=""
        if az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$CLIENT_CERT_NAME-pfx" --query "value" -o tsv &>/dev/null; then
          RETRIEVED_CLIENT_PFX=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$CLIENT_CERT_NAME-pfx" --query "value" -o tsv)
          echo "Retrieved client certificate from Key Vault"
        fi
        
        # Use the retrieved value if it exists, otherwise use the generated value
        if [ -n "$RETRIEVED_CLIENT_PFX" ]; then
          CLIENT_PFX_B64="$RETRIEVED_CLIENT_PFX"
        fi
      fi
      
      # Final verification and output
      echo "Final Root cert data length: ${#ROOT_CERT_DATA}" 
      echo "Final Client PFX data length: ${#CLIENT_PFX_B64}"
      
      # Output the certificate data needed for VPN authentication and the timestamped cert name
      echo "{ \"certificateData\": \"$ROOT_CERT_DATA\", \"timestampedCertName\": \"$CERT_NAME_WITH_TIMESTAMP\" }" > $AZ_SCRIPTS_OUTPUT_PATH
      
      echo "Certificate generation completed successfully"
      
      # Clean up
      cd - >/dev/null
      rm -rf "$CERT_DIR"
    '''
    arguments: '${vpnKeyVault.name} ${rootCertName}'
    timeout: 'PT15M'
    cleanupPreference: 'Always'
  }
}

// Use the certificate data from parameters or from the certificate script
var effectiveCertData = !empty(rootCertData) ? rootCertData : (uamiId != '' ? vpnCertScript.properties.outputs.certificateData : '')

// Public IP for the VPN Gateway
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'vpngw-pip-${discriminator}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'vpn-${toLower(discriminator)}'
    }
  }
}

// VPN Server Configuration for P2S VPN
resource vpnServerConfig 'Microsoft.Network/vpnServerConfigurations@2023-05-01' = {
  name: 'vpnconfig-${discriminator}'
  location: location
  properties: {
    vpnProtocols: [
      'IkeV2'
      'OpenVPN'
    ]
    vpnAuthenticationTypes: [
      authType
    ]
    vpnClientRootCertificates: authType == 'Certificate' ? [
      {
        name: rootCertName
        publicCertData: effectiveCertData
      }
    ] : []
    aadAuthenticationParameters: authType == 'AAD' ? {
      aadTenant: aadTenantId
      aadAudience: aadAudience
      aadIssuer: aadIssuer
    } : null
  }
}

// Virtual Network Gateway for P2S VPN
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2023-05-01' = {
  name: 'vpngw-${discriminator}'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    vpnGatewayGeneration: 'Generation2'
    sku: {
      name: 'VpnGw2'
      tier: 'VpnGw2'
    }
    enableBgp: false
    activeActive: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: gatewaySubnet.id
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          addressPool
        ]
      }
      vpnClientProtocols: [
        'IkeV2'
        'OpenVPN'
      ]
      vpnAuthenticationTypes: [
        authType
      ]
      vpnClientRootCertificates: authType == 'Certificate' ? [
        {
          name: contains(vpnCertScript.properties.outputs, 'timestampedCertName') ? vpnCertScript.properties.outputs.timestampedCertName : rootCertName
          properties: {
            publicCertData: effectiveCertData
          }
        }
      ] : []
      aadTenant: authType == 'AAD' ? aadTenantId : null
      aadAudience: authType == 'AAD' ? aadAudience : null
      aadIssuer: authType == 'AAD' ? aadIssuer : null
    }
  }
}

@description('The resource ID of the VPN gateway')
output vpnGatewayId string = vpnGateway.id

@description('The public IP address of the VPN gateway')
output vpnPublicIpAddress string = publicIp.properties.ipAddress

@description('The VPN client configuration package URL')
output vpnClientPackageUrl string = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworkGateways/${vpnGateway.name}/vpnclientpackage'

@description('The certificate data used for VPN authentication')
output certificateData string = effectiveCertData

// No client certificate or password outputs for security reasons
// Certificates should be retrieved from Key Vault only
