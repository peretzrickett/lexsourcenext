#!/bin/bash
# Script to test the web app deployment through Front Door

# Color codes for messaging
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

CLIENT_NAME="ClientA"
FRONTDOOR_ENDPOINT="afd-ep-lexsb-ClientA-f0f6huhhecgtc9ep.z03.azurefd.net"
WEBAPP_NAME="app-lexsb-${CLIENT_NAME}"

echo -e "${YELLOW}Testing Front Door endpoint connectivity...${NC}"
echo -e "${YELLOW}Front Door URL: https://${FRONTDOOR_ENDPOINT}${NC}"

# Test Front Door endpoint
echo -e "${YELLOW}Testing HTTP status code from Front Door:${NC}"
fd_status=$(curl -s -o /dev/null -w "%{http_code}" https://${FRONTDOOR_ENDPOINT})

if [ "$fd_status" == "200" ]; then
  echo -e "${GREEN}Front Door returned HTTP 200 OK - Web app is accessible through Front Door!${NC}"
else
  echo -e "${RED}Front Door returned HTTP $fd_status - There might be an issue with the web app or Front Door configuration${NC}"
fi

# Test direct app access (should fail with private endpoints)
echo -e "\n${YELLOW}Testing direct web app access (should fail with private endpoints):${NC}"
echo -e "${YELLOW}Web App URL: https://${WEBAPP_NAME}.azurewebsites.net${NC}"

app_status=$(curl -s -o /dev/null -w "%{http_code}" https://${WEBAPP_NAME}.azurewebsites.net 2>/dev/null || echo "Failed")

if [ "$app_status" == "403" ] || [ "$app_status" == "Failed" ]; then
  echo -e "${GREEN}Direct access is blocked as expected (got $app_status) - Private endpoint protection is working!${NC}"
else
  echo -e "${RED}Direct access returned HTTP $app_status - Private endpoint might not be properly configured${NC}"
fi

# Optional: Perform a simple health check on the web app via Front Door
echo -e "\n${YELLOW}Performing health check on the web app via Front Door...${NC}"
health_content=$(curl -s https://${FRONTDOOR_ENDPOINT})

if echo "$health_content" | grep -q "Lex Demo"; then
  echo -e "${GREEN}Health check passed - Found 'Lex Demo' in the response${NC}"
else
  echo -e "${RED}Health check failed - Did not find expected content in the response${NC}"
  echo -e "${YELLOW}Response preview: ${NC}"
  echo "${health_content:0:200}..."
fi

echo -e "\n${YELLOW}Testing complete!${NC}"