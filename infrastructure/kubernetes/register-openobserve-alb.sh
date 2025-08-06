#!/bin/bash

# Script to update OpenObserve ALB target group with current pod IP
# This script auto-detects all required values

set -e

echo "=== OpenObserve ALB Registration Script ==="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE="aurora-logs"
APP_LABEL="openobserve"
PORT="5080"

# Auto-detect AWS region
REGION=$(aws configure get region || echo "us-east-1")
echo -e "${BLUE}Using AWS Region: ${REGION}${NC}"

# Get current OpenObserve pod IP
echo -e "${BLUE}Finding OpenObserve pod...${NC}"
POD_IP=$(kubectl get pod -n ${NAMESPACE} -l app=${APP_LABEL} -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)

if [ -z "$POD_IP" ]; then
    echo -e "${RED}Error: No OpenObserve pod found in namespace ${NAMESPACE}${NC}"
    echo "Make sure OpenObserve is deployed and running"
    exit 1
fi

echo -e "${GREEN}Found OpenObserve pod IP: ${POD_IP}${NC}"

# Find the ALB and target group
echo -e "${BLUE}Finding OpenObserve ALB...${NC}"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --region ${REGION} \
    --query 'LoadBalancers[?contains(LoadBalancerName, `openobserve`) || contains(LoadBalancerName, `OpenObserve`)].LoadBalancerArn' \
    --output text)

if [ -z "$ALB_ARN" ]; then
    echo -e "${RED}Error: No OpenObserve ALB found${NC}"
    echo "Please ensure the ALB is created via Terraform"
    exit 1
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region ${REGION} \
    --load-balancer-arns ${ALB_ARN} \
    --query 'LoadBalancers[0].DNSName' \
    --output text)

echo -e "${GREEN}Found ALB: ${ALB_DNS}${NC}"

# Get target group ARN
echo -e "${BLUE}Finding target group...${NC}"
TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
    --region ${REGION} \
    --load-balancer-arn ${ALB_ARN} \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

if [ -z "$TARGET_GROUP_ARN" ]; then
    echo -e "${RED}Error: No target group found for ALB${NC}"
    exit 1
fi

echo -e "${GREEN}Found target group${NC}"

# Get current targets
echo -e "${BLUE}Checking current targets...${NC}"
CURRENT_TARGETS=$(aws elbv2 describe-target-health \
    --region ${REGION} \
    --target-group-arn ${TARGET_GROUP_ARN} \
    --query 'TargetHealthDescriptions[*].Target.Id' \
    --output text)

# Deregister old targets
if [ ! -z "$CURRENT_TARGETS" ]; then
    echo -e "${YELLOW}Deregistering old targets...${NC}"
    for target in $CURRENT_TARGETS; do
        if [ "$target" != "$POD_IP" ]; then
            echo "  Removing: ${target}"
            aws elbv2 deregister-targets \
                --region ${REGION} \
                --target-group-arn ${TARGET_GROUP_ARN} \
                --targets Id=${target},Port=${PORT} 2>/dev/null || true
        fi
    done
fi

# Check if new IP is already registered
if echo "$CURRENT_TARGETS" | grep -q "$POD_IP"; then
    echo -e "${GREEN}Pod IP ${POD_IP} is already registered${NC}"
else
    # Register new target
    echo -e "${BLUE}Registering new target: ${POD_IP}:${PORT}${NC}"
    aws elbv2 register-targets \
        --region ${REGION} \
        --target-group-arn ${TARGET_GROUP_ARN} \
        --targets Id=${POD_IP},Port=${PORT}
fi

# Wait for target to become healthy
echo -e "${BLUE}Waiting for target to become healthy...${NC}"
for i in {1..30}; do
    HEALTH_STATUS=$(aws elbv2 describe-target-health \
        --region ${REGION} \
        --target-group-arn ${TARGET_GROUP_ARN} \
        --targets Id=${POD_IP},Port=${PORT} \
        --query 'TargetHealthDescriptions[0].TargetHealth.State' \
        --output text 2>/dev/null || echo "initial")
    
    if [ "$HEALTH_STATUS" == "healthy" ]; then
        echo -e "${GREEN}✓ Target is healthy!${NC}"
        break
    else
        echo -e "  Status: ${HEALTH_STATUS} (attempt ${i}/30)"
        sleep 10
    fi
done

# Show final target health
echo
echo -e "${BLUE}Final target group status:${NC}"
aws elbv2 describe-target-health \
    --region ${REGION} \
    --target-group-arn ${TARGET_GROUP_ARN} \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,Health:TargetHealth.State}' \
    --output table

echo
echo -e "${GREEN}=== OpenObserve ALB Registration Complete! ===${NC}"
echo
echo -e "Access OpenObserve at: ${GREEN}http://${ALB_DNS}${NC}"
echo -e "Credentials: admin@example.com / Complexpass#123"
echo