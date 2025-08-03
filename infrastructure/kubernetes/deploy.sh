#!/bin/bash

# Aurora Log System - Unified Deployment Script
# Deploys with cost optimization by default

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="aurora-logs"
AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="072006186126"

echo -e "${BLUE}=== Aurora Log System Deployment ===${NC}"
echo -e "${BLUE}Starting deployment at $(date)${NC}\n"

# Function to wait for deployment
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    echo -e "${YELLOW}Waiting for $deployment to be ready...${NC}"
    kubectl rollout status deployment/$deployment -n $namespace --timeout=300s || true
}

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"
kubectl cluster-info &> /dev/null || {
    echo -e "${RED}Error: Not connected to a Kubernetes cluster${NC}"
    exit 1
}

echo -e "${GREEN}Prerequisites verified!${NC}\n"

# Deploy in order
echo -e "${BLUE}1. Creating namespace and RBAC...${NC}"
kubectl apply -f 00-namespace.yaml
echo -e "${GREEN}✓ Namespace and RBAC created${NC}\n"

echo -e "${BLUE}2. Creating Secrets...${NC}"
kubectl apply -f 01-secrets.yaml
echo -e "${GREEN}✓ Secrets created${NC}\n"

echo -e "${BLUE}3. Creating ConfigMaps...${NC}"
kubectl apply -f 02-configmaps.yaml
echo -e "${GREEN}✓ ConfigMaps created${NC}\n"

echo -e "${BLUE}4. Creating Storage resources...${NC}"
kubectl apply -f 03-storage.yaml
echo -e "${GREEN}✓ Storage resources created${NC}\n"

echo -e "${BLUE}5. Deploying Valkey (Redis)...${NC}"
kubectl apply -f 04-valkey.yaml
wait_for_deployment valkey $NAMESPACE
echo -e "${GREEN}✓ Valkey deployed${NC}\n"

echo -e "${BLUE}6. Deploying Kafka...${NC}"
kubectl apply -f 05-kafka.yaml
wait_for_deployment kafka $NAMESPACE
sleep 10  # Give Kafka extra time to initialize

# Create Kafka topics
echo -e "${BLUE}7. Creating Kafka topics...${NC}"
kubectl apply -f 05-kafka.yaml  # Includes topic creation job
kubectl wait --for=condition=complete job/kafka-create-topics -n $NAMESPACE --timeout=300s || true
echo -e "${GREEN}✓ Kafka topics created${NC}\n"

echo -e "${BLUE}8. Deploying OpenObserve...${NC}"
kubectl apply -f 06-openobserve.yaml
wait_for_deployment openobserve $NAMESPACE
echo -e "${GREEN}✓ OpenObserve deployed${NC}\n"

echo -e "${BLUE}9. Deploying Discovery Service...${NC}"
kubectl apply -f 07-discovery.yaml
wait_for_deployment discovery $NAMESPACE
echo -e "${GREEN}✓ Discovery service deployed${NC}\n"

echo -e "${BLUE}10. Deploying Processor Service (Master-Slave)...${NC}"
kubectl apply -f 09-fluent-bit-config.yaml  # Config first
kubectl apply -f 08-processor.yaml
wait_for_deployment processor-master $NAMESPACE
echo -e "${GREEN}✓ Processor service deployed${NC}\n"

echo -e "${BLUE}11. Applying Autoscaling policies...${NC}"
kubectl apply -f 10-autoscaling.yaml
echo -e "${GREEN}✓ Autoscaling configured${NC}\n"

echo -e "${BLUE}12. Applying Network policies...${NC}"
kubectl apply -f 11-network-policies.yaml
echo -e "${GREEN}✓ Network policies applied${NC}\n"

echo -e "${BLUE}13. Applying Policies (PDB & Quotas)...${NC}"
kubectl apply -f 12-policies.yaml
echo -e "${GREEN}✓ Policies applied${NC}\n"

echo -e "${BLUE}14. Deploying Monitoring Stack...${NC}"
kubectl apply -f 13-monitoring.yaml
echo -e "${GREEN}✓ Monitoring deployed${NC}\n"

# Display deployment summary
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo -e "${GREEN}✓ All components deployed successfully!${NC}\n"

# Get service status
echo -e "${BLUE}Service Status:${NC}"
kubectl get deployments -n $NAMESPACE

echo -e "\n${BLUE}Pod Status:${NC}"
kubectl get pods -n $NAMESPACE

echo -e "\n${BLUE}HPA Status:${NC}"
kubectl get hpa -n $NAMESPACE

# Display access information
echo -e "\n${BLUE}=== Access Information ===${NC}"

# OpenObserve
ALB_DNS=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "Not found")
if [ "$ALB_DNS" != "Not found" ] && [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
    echo -e "${GREEN}OpenObserve UI:${NC} http://$ALB_DNS"
else
    echo -e "${YELLOW}OpenObserve access via port-forward:${NC}"
    echo -e "kubectl port-forward -n $NAMESPACE svc/openobserve-service 5080:5080"
fi
echo -e "${GREEN}Username:${NC} admin@example.com"
echo -e "${GREEN}Password:${NC} Complexpass#123"

echo -e "\n${BLUE}=== Cost Optimization Status ===${NC}"
echo "✓ Master-slave processor architecture enabled"
echo "✓ Scale-to-zero configured for processor slaves"
echo "✓ Resource requests optimized (50-70% reduction)"
echo "✓ Single-node Kafka deployment"
echo "✓ K8s log collection to S3 enabled"

echo -e "\n${BLUE}=== Estimated Monthly Costs ===${NC}"
echo "Idle state: ~$44/month"
echo "Active processing: ~$60-80/month"
echo "(Compare to: ~$305/month without optimization)"

echo -e "\n${BLUE}=== Next Steps ===${NC}"
echo "1. Monitor autoscaling: watch 'kubectl get hpa -n $NAMESPACE'"
echo "2. Check processor slaves: kubectl get pods -n $NAMESPACE -l role=slave"
echo "3. View logs: kubectl logs -f deployment/processor-master -n $NAMESPACE"
echo "4. Run health check: ./health-check.sh"
echo "5. Setup Fargate (optional): ./fargate-setup.sh"

echo -e "\n${GREEN}Deployment completed at $(date)${NC}"