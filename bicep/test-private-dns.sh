#!/bin/bash
# Script to test DNS resolution for private endpoints
# Run this on the vm-network-tester VM

echo "=== Testing DNS Resolution for Private Endpoints ==="
echo ""

# Global variables
DISCRIMINATOR="lexsb"

# Read clients from JSON file (this function should be run on the deployment machine, not the VM)
get_clients() {
  if [ -f ~/clients.json ]; then
    cat ~/clients.json | jq -r '.parameters.clients.value[].name'
  else
    # Fallback to hardcoded clients if clients.json not available
    echo "ClientA ClientB"
  fi
}

CLIENTS=$(get_clients)

# Function to test DNS resolution
test_dns() {
  local fqdn=$1
  local expected_ip=$2
  local zone=$3
  
  echo -e "\033[33mTesting:\033[0m $fqdn (Expected IP: $expected_ip)"
  result=$(nslookup $fqdn 2>/dev/null)
  exit_code=$?
  
  echo "$result" | grep -v "^$"
  
  if [ $exit_code -ne 0 ]; then
    echo -e "\033[31mFAILED: DNS lookup failed for $fqdn\033[0m"
    return 1
  fi
  
  resolved_ip=$(echo "$result" | grep "Address:" | tail -1 | awk '{print $2}')
  
  if [ "$resolved_ip" == "$expected_ip" ]; then
    echo -e "\033[32mSUCCESS: DNS properly resolved to $resolved_ip\033[0m"
    return 0
  else
    echo -e "\033[31mFAILED: DNS resolved to $resolved_ip instead of $expected_ip\033[0m"
    return 1
  fi
}

# Private DNS zones to test
declare -a ZONES=(
  "privatelink.azurewebsites.net"
  "privatelink.blob.core.windows.net"
  "privatelink.core.windows.net"
  "privatelink.database.windows.net"
  "privatelink.file.core.windows.net"
  "privatelink.insights.azure.com"
  "privatelink.monitor.azure.com"
  "privatelink.vaultcore.azure.net"
)

# Expected IPs for resources (in privateLink subnet)
# These are in the 10.1.3.x range for ClientA's privateLink subnet
SQL_IP="10.1.3.16"
KV_IP="10.1.3.4"
STORAGE_IP="10.1.3.5"
MONITOR_IP="10.1.3.6"

# Process each client
for CLIENT in $CLIENTS; do
  echo "===================================================="
  echo "=== Testing DNS resolution for client: $CLIENT ==="
  echo "===================================================="
  
  # Storage Account Tests
  echo -e "\n=== Blob Storage DNS Tests ==="
  test_dns "stg${DISCRIMINATOR}${CLIENT,,}.privatelink.blob.core.windows.net" "$STORAGE_IP" "privatelink.blob.core.windows.net"
  
  echo -e "\n=== Core Storage DNS Tests ==="
  test_dns "stg${DISCRIMINATOR}${CLIENT,,}.privatelink.core.windows.net" "$STORAGE_IP" "privatelink.core.windows.net"
  
  echo -e "\n=== File Storage DNS Tests ==="
  test_dns "stg${DISCRIMINATOR}${CLIENT,,}.privatelink.file.core.windows.net" "$STORAGE_IP" "privatelink.file.core.windows.net"
  
  # SQL Server Tests
  echo -e "\n=== SQL Server DNS Tests ==="
  test_dns "sql-${DISCRIMINATOR}-${CLIENT}.privatelink.database.windows.net" "$SQL_IP" "privatelink.database.windows.net"
  
  # Key Vault Tests
  echo -e "\n=== Key Vault DNS Tests ==="
  test_dns "pkv-${DISCRIMINATOR}-${CLIENT}.privatelink.vaultcore.azure.net" "$KV_IP" "privatelink.vaultcore.azure.net"
  
  # Monitor/Insights Tests
  echo -e "\n=== Monitor DNS Tests ==="
  test_dns "pai-${DISCRIMINATOR}-${CLIENT}.privatelink.monitor.azure.com" "$MONITOR_IP" "privatelink.monitor.azure.com"
  
  echo -e "\n=== Insights DNS Tests ==="
  test_dns "pai-${DISCRIMINATOR}-${CLIENT}.privatelink.insights.azure.com" "$MONITOR_IP" "privatelink.insights.azure.com"

  # Web App Tests (note: may not have DNS records if AFD manages private links)
  echo -e "\n=== Web App DNS Tests ==="
  echo -e "\033[33mNote: These may not resolve if AFD manages the endpoints\033[0m"
  nslookup "app-${DISCRIMINATOR}-${CLIENT}.privatelink.azurewebsites.net" 2>/dev/null || echo "DNS resolution failed (expected if managed by AFD)"
done

# Test Front Door endpoints
echo -e "\n=== Testing Front Door Endpoints ==="
for CLIENT in $CLIENTS; do
  # Use the known hostnames
  if [ "$CLIENT" == "ClientA" ]; then
    FD_HOSTNAME="afd-ep-lexsb-ClientA-f0f6huhhecgtc9ep.z03.azurefd.net"
  elif [ "$CLIENT" == "ClientB" ]; then
    FD_HOSTNAME="afd-ep-lexsb-ClientB-fqejbbbsh3c2dpax.z03.azurefd.net"
  else
    # Default pattern for other clients
    FD_HOSTNAME="afd-ep-${DISCRIMINATOR}-${CLIENT}"
    echo -e "\033[33mUsing default hostname pattern for unknown client\033[0m"
  fi
  
  echo -e "\033[33mTesting Front Door endpoint:\033[0m $FD_HOSTNAME"
  nslookup "$FD_HOSTNAME"
  echo ""
done

# Test direct app access (should fail with private endpoints)
echo -e "\n=== Testing Direct App Access (should fail with private endpoints) ==="
for CLIENT in $CLIENTS; do
  APP_NAME="app-${DISCRIMINATOR}-${CLIENT}"
  echo -e "\033[33mTesting direct app access:\033[0m $APP_NAME.azurewebsites.net"
  nslookup "$APP_NAME.azurewebsites.net"
  echo ""
done

echo "=== DNS Testing Complete ==="