#!/bin/bash

# Titats Deployment Script
# Run: chmod +x deploy.sh && ./deploy.sh

set -e

echo "🚀 Deploying Titats - ckBTC Tip Jar Platform"
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if dfx is running
if ! dfx ping &> /dev/null; then
    echo -e "${YELLOW}Starting local replica...${NC}"
    dfx start --background --clean
    sleep 3
fi

# Get admin principal
ADMIN=$(dfx identity get-principal)
echo -e "${GREEN}Admin Principal: $ADMIN${NC}"

# Step 1: Deploy Registry first (no dependencies)
echo -e "\n${YELLOW}Step 1: Deploying Registry canister...${NC}"
dfx deploy registry
REGISTRY_ID=$(dfx canister id registry)
echo -e "${GREEN}Registry deployed: $REGISTRY_ID${NC}"

# Step 2: Deploy Treasury (depends on Registry)
echo -e "\n${YELLOW}Step 2: Deploying Treasury canister...${NC}"
dfx deploy treasury --argument "(record { 
    registryCanister = principal \"$REGISTRY_ID\"; 
    admin = principal \"$ADMIN\" 
})"
TREASURY_ID=$(dfx canister id treasury)
echo -e "${GREEN}Treasury deployed: $TREASURY_ID${NC}"

# Step 3: Deploy History (depends on Treasury)
echo -e "\n${YELLOW}Step 3: Deploying History canister...${NC}"
dfx deploy history --argument "(record { 
    treasuryCanister = principal \"$TREASURY_ID\" 
})"
HISTORY_ID=$(dfx canister id history)
echo -e "${GREEN}History deployed: $HISTORY_ID${NC}"

# Step 4: Deploy Main (depends on all others)
echo -e "\n${YELLOW}Step 4: Deploying Main canister...${NC}"
dfx deploy main --argument "(record { 
    registryCanister = principal \"$REGISTRY_ID\"; 
    treasuryCanister = principal \"$TREASURY_ID\"; 
    historyCanister = principal \"$HISTORY_ID\" 
})"
MAIN_ID=$(dfx canister id main)
echo -e "${GREEN}Main deployed: $MAIN_ID${NC}"

# Step 5: Deploy frontend (if exists)
if [ -d "src/frontend" ]; then
    echo -e "\n${YELLOW}Step 5: Deploying Frontend...${NC}"
    dfx deploy frontend
    FRONTEND_ID=$(dfx canister id frontend)
    echo -e "${GREEN}Frontend deployed: $FRONTEND_ID${NC}"
fi

# Summary
echo -e "\n============================================="
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "============================================="
echo ""
echo "Canister IDs:"
echo "  Registry: $REGISTRY_ID"
echo "  Treasury: $TREASURY_ID"  
echo "  History:  $HISTORY_ID"
echo "  Main:     $MAIN_ID"
if [ ! -z "$FRONTEND_ID" ]; then
    echo "  Frontend: $FRONTEND_ID"
fi
echo ""
echo "Local URLs:"
echo "  Main:     http://$MAIN_ID.localhost:4943"
if [ ! -z "$FRONTEND_ID" ]; then
    echo "  Frontend: http://$FRONTEND_ID.localhost:4943"
fi
echo ""

# Save canister IDs to a file for reference
cat > .canister-ids.json << EOF
{
  "registry": "$REGISTRY_ID",
  "treasury": "$TREASURY_ID",
  "history": "$HISTORY_ID",
  "main": "$MAIN_ID",
  "frontend": "${FRONTEND_ID:-null}",
  "admin": "$ADMIN"
}
EOF
echo -e "${GREEN}Canister IDs saved to .canister-ids.json${NC}"

# Test deployment
echo -e "\n${YELLOW}Testing deployment...${NC}"
dfx canister call main getPlatformStats
echo -e "${GREEN}✅ All canisters responding!${NC}"