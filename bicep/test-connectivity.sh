#!/bin/bash
# Script to test network connectivity to private endpoints
# Run this on the vm-network-tester VM

echo "=== Testing Network Connectivity for Private Endpoints ==="
echo ""

# Global variables
DISCRIMINATOR="lexsb"

# Read clients from JSON file
get_clients() {
  if [ -f ~/clients.json ]; then
    cat ~/clients.json | jq -r '.parameters.clients.value[].name'
  else
    # Fallback to hardcoded clients if clients.json not available
    echo "ClientA ClientB"
  fi
}

CLIENTS=$(get_clients)

# Function to test TCP connectivity
test_tcp_connection() {
  local host=$1
  local port=$2
  local description=$3
  
  echo -e "\033[33mTesting TCP connection to:\033[0m $host:$port ($description)"
  
  timeout 5 bash -c "cat < /dev/null > /dev/tcp/$host/$port" 2>/dev/null
  exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    echo -e "\033[32mSUCCESS: TCP connection to $host:$port succeeded\033[0m"
    return 0
  else
    echo -e "\033[31mFAILED: Could not establish TCP connection to $host:$port\033[0m"
    return 1
  fi
}

# Function to test HTTP connectivity
test_http_connectivity() {
  local url=$1
  local expected_code=$2
  local description=$3
  
  echo -e "\033[33mTesting HTTP connectivity to:\033[0m $url ($description)"
  
  response=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$url")
  exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    echo -e "\033[31mFAILED: CURL command failed with exit code $exit_code\033[0m"
    return 1
  fi
  
  if [ "$response" == "$expected_code" ]; then
    echo -e "\033[32mSUCCESS: HTTP response code: $response (expected: $expected_code)\033[0m"
    return 0
  else
    echo -e "\033[31mFAILED: HTTP response code was $response (expected: $expected_code)\033[0m"
    return 1
  fi
}

# Process each client
for CLIENT in $CLIENTS; do
  echo "===================================================="
  echo "=== Testing connectivity for client: $CLIENT ==="
  echo "===================================================="

  # Storage Account Tests
  echo -e "\n=== Storage Account Connectivity Tests ==="
  test_tcp_connection "stg${DISCRIMINATOR}${CLIENT,,}.privatelink.blob.core.windows.net" 443 "Blob Storage"
  
  # SQL Server Tests
  echo -e "\n=== SQL Server Connectivity Tests ==="
  test_tcp_connection "sql-${DISCRIMINATOR}-${CLIENT}.privatelink.database.windows.net" 1433 "SQL Server"
  
  # Key Vault Tests
  echo -e "\n=== Key Vault Connectivity Tests ==="
  test_tcp_connection "pkv-${DISCRIMINATOR}-${CLIENT}.privatelink.vaultcore.azure.net" 443 "Key Vault"
  
  # App Insights Tests
  echo -e "\n=== App Insights Connectivity Tests ==="
  test_tcp_connection "pai-${DISCRIMINATOR}-${CLIENT}.privatelink.monitor.azure.com" 443 "App Insights"
  
  # Front Door Tests
  echo -e "\n=== Front Door Endpoint Tests ==="
  
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
  test_http_connectivity "https://$FD_HOSTNAME" "200" "Front Door endpoint"
  
  # Direct App Access Tests (should fail with private endpoints enabled)
  echo -e "\n=== Direct App Access Tests (should fail with private endpoints) ==="
  test_http_connectivity "https://app-${DISCRIMINATOR}-${CLIENT}.azurewebsites.net" "403" "Direct access to app (should be blocked)"
  
  echo ""
done

echo "=== Connectivity Testing Complete ==="