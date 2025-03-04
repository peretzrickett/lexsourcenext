// Module for managing VPN certificate operations
@description('Name of the Key Vault to store certificates')
param keyVaultName string

@description('Certificate name to create or retrieve')
param certificateName string

@description('Azure region for deployment script')
param location string

@description('Resource ID of user-assigned managed identity to run deployment scripts')
param uamiId string

// Create the Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
  }
}

// Reference existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: last(split(uamiId, '/'))
}

// Give the UAMI access to the Key Vault
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: uami.properties.principalId
        permissions: {
          certificates: [
            'get'
            'list'
            'create'
            'import'
          ]
          secrets: [
            'get'
            'list'
            'set'
          ]
          keys: [
            'get'
            'list'
            'create'
          ]
        }
      }
    ]
  }
}

// Generate certificate deployment script
resource generateCertScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'vpn-cert-operations-${certificateName}'
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
      
      KEY_VAULT_NAME=$1
      CERT_NAME=$2
      
      # Check if certificate exists in Key Vault
      CERT=$(az keyvault certificate show --vault-name "$KEY_VAULT_NAME" --name "$CERT_NAME" 2>/dev/null)
      
      if [ $? -eq 0 ]; then
        # Certificate exists - retrieve it
        echo "Certificate $CERT_NAME exists in Key Vault, retrieving..."
        
        # Retrieve the public certificate data from Key Vault
        SECRET_INFO=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "$CERT_NAME-public" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
          # Secret exists
          PUBLIC_CERT_DATA=$(echo $SECRET_INFO | jq -r .value)
          echo "Successfully retrieved certificate data"
          echo "{ \"certificateData\": \"$PUBLIC_CERT_DATA\" }" > $AZ_SCRIPTS_OUTPUT_PATH
          exit 0
        else
          # Public cert data not found - will create a new one
          echo "Cannot find public certificate data in Key Vault, creating new certificate..."
        fi
      fi
      
      # Generate a new certificate
      echo "Generating new certificate: $CERT_NAME"
      
      # Create temporary directory
      TEMP_DIR=$(mktemp -d)
      PFX_PATH="$TEMP_DIR/$CERT_NAME.pfx"
      CER_PATH="$TEMP_DIR/$CERT_NAME.cer"
      KEY_PATH="$TEMP_DIR/$CERT_NAME.key"
      CSR_PATH="$TEMP_DIR/$CERT_NAME.csr"
      PEM_PATH="$TEMP_DIR/$CERT_NAME.pem"
      CERT_PASSWORD="Temp123!"
      
      echo "Generating certificate files in: $TEMP_DIR"
      
      # Generate private key
      openssl genrsa -out "$KEY_PATH" 2048
      
      # Generate CSR
      openssl req -new -key "$KEY_PATH" -out "$CSR_PATH" -subj "/CN=$CERT_NAME" -nodes
      
      # Generate self-signed certificate
      openssl x509 -req -days 3650 -in "$CSR_PATH" -signkey "$KEY_PATH" -out "$PEM_PATH"
      
      # Create PFX file for Key Vault with password
      openssl pkcs12 -export -out "$PFX_PATH" -inkey "$KEY_PATH" -in "$PEM_PATH" -password "pass:$CERT_PASSWORD"
      
      # Create CER file for VPN
      openssl x509 -inform PEM -outform DER -in "$PEM_PATH" -out "$CER_PATH"
      
      # Base64 encode the CER file
      PUBLIC_CERT_BASE64=$(base64 -i "$CER_PATH" | tr -d '\n')
      
      # Upload PFX to Key Vault as certificate
      az keyvault certificate import --vault-name "$KEY_VAULT_NAME" \
                                    --name "$CERT_NAME" \
                                    --file "$PFX_PATH" \
                                    --password "$CERT_PASSWORD"
                                    
      # Save the public cert as a secret in Key Vault
      az keyvault secret set --vault-name "$KEY_VAULT_NAME" \
                            --name "$CERT_NAME-public" \
                            --value "$PUBLIC_CERT_BASE64"
      
      # Clean up temp files
      rm -rf "$TEMP_DIR"
      
      # Output
      echo "Certificate generated/retrieved successfully"
      echo "{ \"certificateData\": \"$PUBLIC_CERT_BASE64\" }" > $AZ_SCRIPTS_OUTPUT_PATH
    '''
    arguments: '${keyVaultName} ${certificateName}'
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
  }
  dependsOn: [
    keyVaultAccessPolicy
  ]
}

@description('Base64-encoded public certificate data for VPN authentication')
output certificateData string = generateCertScript.properties.outputs.certificateData