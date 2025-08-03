#!/bin/bash

# Aurora Log System - Quick Start Script
# This script sets up and deploys everything in one go

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Aurora Log System Quick Start ===${NC}"
echo ""

# Run IAM setup
echo -e "${BLUE}Setting up IAM roles...${NC}"
./setup-iam.sh

echo ""

# Deploy everything
echo -e "${BLUE}Deploying Aurora Log System...${NC}"
./deploy.sh

echo ""

# Run validation
echo -e "${BLUE}Validating deployment...${NC}"
./validate.sh

echo ""
echo -e "${GREEN}✓ Aurora Log System is ready!${NC}"
echo ""
echo "Next steps:"
echo "  - View logs: make logs-discovery"
echo "  - Check health: make health-check"
echo "  - See status: make status"