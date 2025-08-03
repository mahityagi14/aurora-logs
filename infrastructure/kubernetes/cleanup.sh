#!/bin/bash

# Aurora Log System - Complete Cleanup Script
# This script removes all Aurora Log System components from Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="aurora-logs"


echo -e "${BLUE}=== Aurora Log System Cleanup ===${NC}"
echo -e "${RED}WARNING: This will delete all Aurora Log System resources!${NC}"
echo -n "Are you sure you want to continue? (yes/no): "
read -r response

if [ "$response" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "\n${BLUE}Starting cleanup at $(date)${NC}\n"

# Deregister OpenObserve from ALB (if exists)
echo -e "${BLUE}1. Deregistering OpenObserve from ALB...${NC}"
ALB_ARN=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
    TG_ARN=$(aws elbv2 describe-target-groups --load-balancer-arn $ALB_ARN --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
    if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
        TARGETS=$(aws elbv2 describe-target-health --target-group-arn $TG_ARN --query 'TargetHealthDescriptions[].Target' --output json 2>/dev/null || echo "[]")
        if [ "$TARGETS" != "[]" ]; then
            aws elbv2 deregister-targets --target-group-arn $TG_ARN --targets "$TARGETS" 2>/dev/null || true
            echo -e "${GREEN}✓ Targets deregistered from ALB${NC}"
        fi
    fi
else
    echo -e "${YELLOW}OpenObserve ALB not found, skipping${NC}"
fi

# Delete resources in reverse order
echo -e "\n${BLUE}2. Deleting resources in reverse order...${NC}"

# Delete network policies
kubectl delete -f 11-network-policies.yaml 2>/dev/null || true

# Delete autoscaling
kubectl delete -f 10-autoscaling.yaml 2>/dev/null || true

# Delete Fluent Bit config
kubectl delete -f 09-fluent-bit-config.yaml 2>/dev/null || true

# Delete applications
kubectl delete -f 08-processor.yaml 2>/dev/null || true
kubectl delete -f 07-discovery.yaml 2>/dev/null || true
kubectl delete -f 06-openobserve.yaml 2>/dev/null || true
kubectl delete -f 05-kafka.yaml 2>/dev/null || true
kubectl delete -f 04-valkey.yaml 2>/dev/null || true

# Delete storage
kubectl delete -f 03-storage.yaml 2>/dev/null || true

# Delete config and secrets
kubectl delete -f 02-configmaps.yaml 2>/dev/null || true
kubectl delete -f 01-secrets.yaml 2>/dev/null || true

# Delete namespace and RBAC
kubectl delete -f 00-namespace.yaml 2>/dev/null || true

# Delete namespace (this will delete any remaining resources)
echo -e "\n${BLUE}3. Deleting namespace...${NC}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "Deleting namespace $NAMESPACE (this may take a moment)..."
    kubectl delete namespace $NAMESPACE --timeout=60s
    echo -e "${GREEN}✓ Namespace deleted${NC}"
else
    echo -e "${YELLOW}Namespace $NAMESPACE not found${NC}"
fi

# Optional: Delete IAM roles (commented out by default for safety)
echo -e "\n${BLUE}4. IAM roles...${NC}"
echo -e "${YELLOW}Note: IAM roles are preserved for safety.${NC}"
echo -e "To delete IAM roles, run:"
echo -e "  ./cleanup-iam.sh"

# Summary
echo -e "\n${BLUE}=== Cleanup Summary ===${NC}"
echo -e "${GREEN}✓ All Aurora Log System resources have been removed${NC}"
echo -e "\nCleanup completed at $(date)"

# Final check
echo -e "\n${BLUE}Verifying cleanup...${NC}"
REMAINING=$(kubectl get all -n $NAMESPACE 2>&1 | grep -v "No resources found" | grep -v "NotFound" | wc -l || echo "0")
if [ "$REMAINING" -eq "0" ]; then
    echo -e "${GREEN}✓ Cleanup verified - no resources remaining${NC}"
else
    echo -e "${YELLOW}Warning: Some resources may still exist in namespace $NAMESPACE${NC}"
    kubectl get all -n $NAMESPACE 2>/dev/null || true
fi