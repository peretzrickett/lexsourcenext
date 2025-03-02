#!/bin/bash

# Post-deployment validation script to verify infrastructure components
# Validates:
# 1. Private DNS zone A records
# 2. Front Door components (origin groups, origins, endpoints, routes)
# 3. Network connectivity via vm-network-tester

# Color codes for output formatting
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Main validation function
validate_deployment() {
    echo -e "\n${BLUE}=== STARTING POST-DEPLOYMENT VALIDATION ===${NC}\n"
    
    # Get subscription info
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    echo -e "${BLUE}Target subscription:${NC} $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    
    # Get client names from clients.json
    CLIENT_NAMES=$(cat clients.json | jq -r '.parameters.clients.value[].name')
    DISCRIMINATOR="lexsb" # Hardcoded for now
    
    # Validate all components
    validate_private_dns
    validate_frontdoor
    validate_network_connectivity
    
    # Print overall validation summary
    echo -e "\n${BLUE}=== VALIDATION SUMMARY ===${NC}"
    if [ $FAILURES -eq 0 ]; then
        echo -e "${GREEN}✓ All validation checks passed successfully${NC}"
    else
        echo -e "${RED}✗ $FAILURES validation checks failed${NC}"
        echo -e "${YELLOW}Review details above for specific failures${NC}"
    fi
}

# Initialize counter for failed checks
FAILURES=0

# Function to check Private DNS zones
validate_private_dns() {
    echo -e "\n${BLUE}=== VALIDATING PRIVATE DNS ZONES ===${NC}"
    
    # List of expected DNS zones
    DNS_ZONES=(
        "privatelink.azurewebsites.net"
        "privatelink.blob.core.windows.net"
        "privatelink.database.windows.net"
        "privatelink.vaultcore.azure.net"
        "privatelink.monitor.azure.com"
    )
    
    # Check if each zone exists
    for ZONE in "${DNS_ZONES[@]}"; do
        echo -e "\n${YELLOW}Checking DNS zone:${NC} $ZONE"
        ZONE_EXISTS=$(az network private-dns zone show --resource-group rg-central --name "$ZONE" --query "name" -o tsv 2>/dev/null)
        
        if [ -n "$ZONE_EXISTS" ]; then
            echo -e "${GREEN}✓ DNS Zone exists:${NC} $ZONE"
            
            # Get and check A records for this zone
            echo -e "${YELLOW}Checking A records for zone:${NC} $ZONE"
            A_RECORDS=$(az network private-dns record-set a list --resource-group rg-central --zone-name "$ZONE" --query "[].name" -o tsv)
            
            if [ -n "$A_RECORDS" ]; then
                echo -e "${GREEN}✓ Found A records:${NC}"
                for RECORD in $A_RECORDS; do
                    IP=$(az network private-dns record-set a show --resource-group rg-central --zone-name "$ZONE" --name "$RECORD" --query "aRecords[0].ipv4Address" -o tsv)
                    echo -e "  - $RECORD → $IP"
                done
            else
                echo -e "${RED}✗ No A records found for zone:${NC} $ZONE"
                ((FAILURES++))
            fi
            
            # Check virtual network links
            echo -e "${YELLOW}Checking virtual network links:${NC}"
            VNET_LINKS=$(az network private-dns link vnet list --resource-group rg-central --zone-name "$ZONE" --query "[].name" -o tsv)
            
            if [ -n "$VNET_LINKS" ]; then
                echo -e "${GREEN}✓ Found VNet links:${NC}"
                for LINK in $VNET_LINKS; do
                    echo -e "  - $LINK"
                done
            else
                echo -e "${RED}✗ No virtual network links found for zone:${NC} $ZONE"
                ((FAILURES++))
            fi
        else
            echo -e "${RED}✗ DNS Zone not found:${NC} $ZONE"
            ((FAILURES++))
        fi
    done
}

# Function to check Front Door components
validate_frontdoor() {
    echo -e "\n${BLUE}=== VALIDATING FRONT DOOR COMPONENTS ===${NC}"
    
    # Check if Front Door profile exists
    FRONT_DOOR_NAME="globalFrontDoor"
    echo -e "\n${YELLOW}Checking Front Door profile:${NC} $FRONT_DOOR_NAME"
    
    FD_EXISTS=$(az afd profile show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --query "name" -o tsv 2>/dev/null)
    
    if [ -n "$FD_EXISTS" ]; then
        echo -e "${GREEN}✓ Front Door profile exists:${NC} $FRONT_DOOR_NAME"
        
        # Check for each client's components
        for CLIENT in $CLIENT_NAMES; do
            echo -e "\n${YELLOW}Checking Front Door components for client:${NC} $CLIENT"
            
            # Check origin group
            OG_NAME="afd-og-${DISCRIMINATOR}-${CLIENT}"
            OG_EXISTS=$(az afd origin-group show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --origin-group-name "$OG_NAME" --query "name" -o tsv 2>/dev/null)
            
            if [ -n "$OG_EXISTS" ]; then
                echo -e "${GREEN}✓ Origin group exists:${NC} $OG_NAME"
            else
                echo -e "${RED}✗ Origin group not found:${NC} $OG_NAME"
                ((FAILURES++))
            fi
            
            # Check origin
            O_NAME="afd-o-${DISCRIMINATOR}-${CLIENT}"
            O_EXISTS=$(az afd origin show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --origin-group-name "$OG_NAME" --origin-name "$O_NAME" --query "name" -o tsv 2>/dev/null)
            
            if [ -n "$O_EXISTS" ]; then
                echo -e "${GREEN}✓ Origin exists:${NC} $O_NAME"
                
                # Check private link status by looking at the App Service side
                # First get the App Service resource ID from the sharedPrivateLinkResource
                APP_ID=$(az afd origin show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --origin-group-name "$OG_NAME" --origin-name "$O_NAME" --query "sharedPrivateLinkResource.privateLink.id" -o tsv 2>/dev/null)
                
                if [ -n "$APP_ID" ]; then
                    PL_STATUS=$(az network private-endpoint-connection list --id "$APP_ID" --query "[0].properties.privateLinkServiceConnectionState.status" -o tsv 2>/dev/null)
                else
                    # Fallback to older API version checks
                    PL_STATUS=$(az afd origin show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --origin-group-name "$OG_NAME" --origin-name "$O_NAME" --query "properties.privateLinkStatus" -o tsv 2>/dev/null)
                fi
                
                if [ "$PL_STATUS" = "Approved" ]; then
                    echo -e "${GREEN}✓ Private link status:${NC} $PL_STATUS"
                else
                    echo -e "${RED}✗ Private link status is not Approved:${NC} $PL_STATUS"
                    ((FAILURES++))
                fi
            else
                echo -e "${RED}✗ Origin not found:${NC} $O_NAME"
                ((FAILURES++))
            fi
            
            # Check endpoint
            EP_NAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
            EP_EXISTS=$(az afd endpoint show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --endpoint-name "$EP_NAME" --query "name" -o tsv 2>/dev/null)
            
            if [ -n "$EP_EXISTS" ]; then
                echo -e "${GREEN}✓ Endpoint exists:${NC} $EP_NAME"
                
                # Get and show the hostname
                HOSTNAME=$(az afd endpoint show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --endpoint-name "$EP_NAME" --query "hostName" -o tsv)
                echo -e "  - Hostname: $HOSTNAME"
            else
                echo -e "${RED}✗ Endpoint not found:${NC} $EP_NAME"
                ((FAILURES++))
            fi
            
            # Check route
            RT_NAME="afd-rt-${DISCRIMINATOR}-${CLIENT}"
            RT_EXISTS=$(az afd route show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --endpoint-name "$EP_NAME" --route-name "$RT_NAME" --query "name" -o tsv 2>/dev/null)
            
            if [ -n "$RT_EXISTS" ]; then
                echo -e "${GREEN}✓ Route exists:${NC} $RT_NAME"
            else
                echo -e "${RED}✗ Route not found:${NC} $RT_NAME"
                ((FAILURES++))
            fi
        done
    else
        echo -e "${RED}✗ Front Door profile not found:${NC} $FRONT_DOOR_NAME"
        ((FAILURES++))
    fi
}

# Function to check network connectivity via vm-network-tester
validate_network_connectivity() {
    echo -e "\n${BLUE}=== VALIDATING NETWORK CONNECTIVITY ===${NC}"
    
    # Get VM network tester info
    VM_NAME="vm-network-tester"
    VM_RG="rg-central"
    
    echo -e "${YELLOW}Checking VM status:${NC} $VM_NAME"
    VM_EXISTS=$(az vm show --resource-group "$VM_RG" --name "$VM_NAME" --query "name" -o tsv 2>/dev/null)
    
    if [ -n "$VM_EXISTS" ]; then
        echo -e "${GREEN}✓ VM exists:${NC} $VM_NAME"
        
        # Check VM power state
        POWER_STATE=$(az vm get-instance-view --resource-group "$VM_RG" --name "$VM_NAME" --query "instanceView.statuses[1].displayStatus" -o tsv)
        
        if [[ "$POWER_STATE" == *"running"* ]]; then
            echo -e "${GREEN}✓ VM is running:${NC} $POWER_STATE"
            
            # Run network tests via SSH
            echo -e "${YELLOW}Running network connectivity tests via SSH...${NC}"
            
            # Get Firewall's public IP for VM access
            FW_IP=$(az network public-ip show --resource-group rg-central --name ip-globalFirewall --query ipAddress -o tsv 2>/dev/null)
            
            if [ -n "$FW_IP" ]; then
                echo -e "${GREEN}✓ Firewall has public IP:${NC} $FW_IP"
                echo -e "${YELLOW}To run DNS tests manually:${NC}"
                echo -e "  1. Connect to VM: ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@$FW_IP"
                echo -e "  2. Copy the test scripts: scp -i ~/.ssh/vm-network-tester_key.pem test-private-dns.sh test-connectivity.sh clients.json azureuser@$FW_IP:~/"
                echo -e "  3. Run tests: ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@$FW_IP \"bash ~/test-private-dns.sh\""
                echo -e "  4. Check connectivity: ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@$FW_IP \"bash ~/test-connectivity.sh\""
                
                # For each client, test name resolution manually
                for CLIENT in $CLIENT_NAMES; do
                    # Test name resolution for app service and other services
                    echo -e "\n${YELLOW}Testing endpoints for client:${NC} $CLIENT"
                    
                    # Define endpoints to test
                    APP_HOSTNAME="app-${DISCRIMINATOR}-${CLIENT}.privatelink.azurewebsites.net"
                    SQL_HOSTNAME="sql-${DISCRIMINATOR}-${CLIENT}.privatelink.database.windows.net"
                    KV_HOSTNAME="pkv-${DISCRIMINATOR}-${CLIENT}.privatelink.vaultcore.azure.net"
                    STORAGE_HOSTNAME="stg${DISCRIMINATOR}${CLIENT}.privatelink.blob.core.windows.net"
                    FRONTDOOR_HOSTNAME=$(az afd endpoint show --resource-group rg-central --profile-name "$FRONT_DOOR_NAME" --endpoint-name "afd-ep-${DISCRIMINATOR}-${CLIENT}" --query "hostName" -o tsv 2>/dev/null)
                    
                    echo -e "${YELLOW}SQL Server:${NC} $SQL_HOSTNAME"
                    echo -e "${YELLOW}Key Vault:${NC} $KV_HOSTNAME"
                    echo -e "${YELLOW}Storage:${NC} $STORAGE_HOSTNAME"
                    echo -e "${YELLOW}Front Door:${NC} $FRONTDOOR_HOSTNAME"
                    
                    test_dns_resolution() {
                        local hostname=$1
                        echo -e "${YELLOW}Testing DNS resolution for:${NC} $hostname"
                        
                        # Try to run the test via SSH using Firewall IP
                        RESULT=$(ssh -o StrictHostKeyChecking=no -i "~/.ssh/vm-network-tester_key.pem" "azureuser@$FW_IP" "nslookup $hostname" 2>/dev/null)
                        SSH_STATUS=$?
                        
                        if [ $SSH_STATUS -eq 0 ]; then
                            if [[ "$RESULT" == *"Non-authoritative answer"* ]]; then
                                echo -e "${GREEN}✓ DNS resolution successful:${NC}"
                                # Extract IP from nslookup result
                                IP=$(echo "$RESULT" | grep "Address:" | tail -n1 | awk '{print $2}')
                                echo -e "  $hostname → $IP"
                                
                                # Test TCP connectivity on port 443
                                echo -e "${YELLOW}Testing TCP connectivity to $hostname:443...${NC}"
                                CONN_RESULT=$(ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "$SSH_USER@$VM_IP" "timeout 5 nc -zv $hostname 443 2>&1" 2>/dev/null)
                                
                                if [[ "$CONN_RESULT" == *"succeeded"* ]]; then
                                    echo -e "${GREEN}✓ TCP connection successful to $hostname:443${NC}"
                                else
                                    echo -e "${RED}✗ TCP connection failed to $hostname:443${NC}"
                                    ((FAILURES++))
                                fi
                            else
                                echo -e "${RED}✗ DNS resolution failed for:${NC} $hostname"
                                echo "$RESULT"
                                ((FAILURES++))
                            fi
                        else
                            echo -e "${RED}✗ SSH connection failed. Cannot test DNS resolution.${NC}"
                            ((FAILURES++))
                        fi
                    }
                    
                    # Run tests for each service endpoint
                    test_dns_resolution "$APP_HOSTNAME"
                    test_dns_resolution "$SQL_HOSTNAME"
                    test_dns_resolution "$KV_HOSTNAME"
                    test_dns_resolution "$STORAGE_HOSTNAME"
                    
                    # Test Front Door endpoint connectivity
                    FD_HOSTNAME="afd-ep-${DISCRIMINATOR}-${CLIENT}.z01.azurefd.net"
                    echo -e "\n${YELLOW}Testing Front Door endpoint:${NC} $FD_HOSTNAME"
                    
                    FD_RESULT=$(ssh -o StrictHostKeyChecking=no -i "~/.ssh/vm-network-tester_key.pem" "azureuser@$FW_IP" "curl -s -o /dev/null -w '%{http_code}' https://$FD_HOSTNAME" 2>/dev/null)
                    
                    if [ "$FD_RESULT" = "200" ] || [ "$FD_RESULT" = "302" ]; then
                        echo -e "${GREEN}✓ Front Door connection successful:${NC} HTTP $FD_RESULT"
                    else
                        echo -e "${RED}✗ Front Door connection failed:${NC} HTTP $FD_RESULT"
                        ((FAILURES++))
                    fi
                done
            else
                echo -e "${RED}✗ VM does not have a public IP address. Cannot run SSH tests.${NC}"
                ((FAILURES++))
            fi
        else
            echo -e "${RED}✗ VM is not running:${NC} $POWER_STATE"
            echo -e "${YELLOW}Please start the VM to run network tests.${NC}"
            echo -e "${YELLOW}After starting the VM, connect via the Firewall IP:${NC}"
            echo -e "  ssh -i ~/.ssh/vm-network-tester_key.pem azureuser@$FW_IP"
            ((FAILURES++))
        fi
    else
        echo -e "${RED}✗ VM not found:${NC} $VM_NAME in resource group $VM_RG"
        echo -e "${YELLOW}Unable to perform network connectivity tests.${NC}"
        echo -e "${YELLOW}Check that the VM exists and that the Firewall NAT rule is properly configured.${NC}"
        ((FAILURES++))
    fi
}

# Run the validation
validate_deployment

exit $FAILURES