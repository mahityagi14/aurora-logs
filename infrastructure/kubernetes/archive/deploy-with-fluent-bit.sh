#!/bin/bash

# Aurora Log System - Deployment with Fluent Bit
# This script deploys the processor with Fluent Bit sidecar for flexible log parsing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Aurora Log System - Fluent Bit Deployment ===${NC}"
echo -e "${BLUE}This will update the processor to use Fluent Bit for log parsing${NC}\n"

# Check if base system is deployed
if ! kubectl get deployment processor -n aurora-logs &> /dev/null; then
    echo -e "${RED}Error: Processor deployment not found. Please run ./deploy.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}1. Deploying Fluent Bit configuration...${NC}"
kubectl apply -f 11-fluent-bit-config.yaml
echo -e "${GREEN}✓ Fluent Bit configuration deployed${NC}\n"

echo -e "${BLUE}2. Creating backup of current processor deployment...${NC}"
kubectl get deployment processor -n aurora-logs -o yaml > processor-backup-$(date +%Y%m%d-%H%M%S).yaml
echo -e "${GREEN}✓ Backup created${NC}\n"

echo -e "${BLUE}3. Updating ConfigMap for Fluent Bit integration...${NC}"
kubectl apply -f 02-configmaps-fluent-bit.yaml
echo -e "${GREEN}✓ ConfigMap updated${NC}\n"

echo -e "${BLUE}4. Deploying processor with Fluent Bit sidecar...${NC}"
kubectl apply -f 08-processor-with-fluent-bit.yaml
echo -e "${GREEN}✓ Processor with Fluent Bit deployed${NC}\n"

echo -e "${BLUE}5. Waiting for rollout to complete...${NC}"
kubectl rollout status deployment/processor -n aurora-logs --timeout=300s
echo -e "${GREEN}✓ Rollout completed${NC}\n"

# Verify Fluent Bit is running
echo -e "${BLUE}6. Verifying Fluent Bit status...${NC}"
POD=$(kubectl get pods -n aurora-logs -l app=processor -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD" ]; then
    if kubectl get pod $POD -n aurora-logs -o jsonpath='{.spec.containers[*].name}' | grep -q fluent-bit; then
        echo -e "${GREEN}✓ Fluent Bit sidecar is running${NC}"
        
        # Check Fluent Bit health
        if kubectl exec -n aurora-logs $POD -c fluent-bit -- wget -q -O- http://localhost:2020/api/v1/health 2>/dev/null | grep -q "ok"; then
            echo -e "${GREEN}✓ Fluent Bit health check passed${NC}"
        else
            echo -e "${YELLOW}⚠ Fluent Bit health check pending${NC}"
        fi
    else
        echo -e "${RED}✗ Fluent Bit sidecar not found${NC}"
    fi
fi

echo -e "\n${BLUE}=== Deployment Summary ===${NC}"
echo -e "${GREEN}✓ Fluent Bit integration deployed successfully!${NC}\n"

echo -e "${BLUE}Architecture:${NC}"
echo "Processor → TCP Forward (localhost:24224) → Fluent Bit → OpenObserve"

echo -e "\n${BLUE}Monitoring:${NC}"
echo "1. Fluent Bit logs: kubectl logs -n aurora-logs deployment/processor -c fluent-bit"
echo "2. Fluent Bit metrics: kubectl port-forward -n aurora-logs deployment/processor 2020:2020"
echo "   Then visit: http://localhost:2020/api/v1/metrics"

echo -e "\n${BLUE}Configuration:${NC}"
echo "- Parsers: kubectl edit configmap fluent-bit-parsers -n aurora-logs"
echo "- Main config: kubectl edit configmap fluent-bit-config -n aurora-logs"

echo -e "\n${BLUE}Rollback:${NC}"
echo "To rollback to processor-only parsing:"
echo "1. kubectl apply -f 02-configmaps.yaml"
echo "2. kubectl apply -f 08-processor.yaml"

echo -e "\n${GREEN}Deployment completed at $(date)${NC}"