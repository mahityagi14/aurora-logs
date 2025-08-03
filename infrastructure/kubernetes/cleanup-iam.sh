#!/bin/bash

# Aurora Log System - IAM Cleanup Script
# This script removes IAM roles created for the Aurora Log System

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Aurora Log System IAM Cleanup ===${NC}"
echo -e "${RED}WARNING: This will delete all Aurora Log System IAM roles!${NC}"
echo -n "Are you sure you want to continue? (yes/no): "
read -r response

if [ "$response" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "\n${BLUE}Starting IAM cleanup...${NC}\n"

# Function to delete IAM role
delete_iam_role() {
    local role_name=$1
    local policy_name=$2
    
    echo -n "Deleting IAM role $role_name... "
    
    # Check if role exists
    if aws iam get-role --role-name $role_name &> /dev/null; then
        # Delete inline policies
        if [ -n "$policy_name" ]; then
            aws iam delete-role-policy --role-name $role_name --policy-name $policy_name 2>/dev/null || true
        fi
        
        # Delete the role
        aws iam delete-role --role-name $role_name
        echo -e "${GREEN}DELETED${NC}"
    else
        echo -e "${YELLOW}NOT FOUND${NC}"
    fi
}

# Delete Discovery Service IAM Role
delete_iam_role "AuroraLogDiscoveryRole" "discovery-policy"

# Delete Processor Service IAM Role
delete_iam_role "AuroraLogProcessorRole" "processor-policy"

# Delete OpenObserve Service IAM Role
delete_iam_role "AuroraLogOpenObserveRole" "openobserve-policy"

echo -e "\n${BLUE}=== IAM Cleanup Summary ===${NC}"
echo -e "${GREEN}✓ All Aurora Log System IAM roles have been removed${NC}"