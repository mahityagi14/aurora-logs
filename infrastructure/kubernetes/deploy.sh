#!/bin/bash

set -e

echo "=== Aurora Log System - Kubernetes Deployment ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo -e "${RED}AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Function to wait for deployment
wait_for_deployment() {
    local deployment=$1
    local namespace=$2
    echo -n "Waiting for $deployment to be ready..."
    
    if kubectl wait --for=condition=available --timeout=300s deployment/$deployment -n $namespace; then
        echo -e " ${GREEN}✓${NC}"
        return 0
    else
        echo -e " ${RED}✗${NC}"
        return 1
    fi
}

# Step 1: Clean up existing deployment
echo -e "${YELLOW}Step 1: Cleaning up existing deployment...${NC}"
if [ -f "./cleanup.sh" ]; then
    ./cleanup.sh
else
    echo "cleanup.sh not found, skipping cleanup"
fi
echo ""

# Step 2: Create namespace and RBAC
echo -e "${YELLOW}Step 2: Creating namespace and RBAC...${NC}"
kubectl apply -f 01-namespace-rbac.yaml
echo ""

# Step 3: Create ConfigMaps and Secrets
echo -e "${YELLOW}Step 3: Creating ConfigMaps and Secrets...${NC}"
kubectl apply -f 02-config-secrets.yaml
echo ""

# Step 4: Create Services
echo -e "${YELLOW}Step 4: Creating Services...${NC}"
kubectl apply -f 03-services.yaml
echo ""

# Step 5: Deploy Valkey
echo -e "${YELLOW}Step 5: Deploying Valkey...${NC}"
kubectl apply -f 04-valkey.yaml
wait_for_deployment "valkey" "aurora-logs"
echo ""

# Step 6: Deploy all main components
echo -e "${YELLOW}Step 6: Deploying main components (Kafka, OpenObserve, Discovery, Processor)...${NC}"

# Deploy all from deployments file
kubectl apply -f 04-deployments.yaml

# Wait for each deployment
wait_for_deployment "kafka" "aurora-logs"
wait_for_deployment "openobserve" "aurora-logs"

# Wait for Kafka to be fully ready before creating topics
echo "Waiting for Kafka to initialize..."
sleep 30

# Step 7: Create Kafka topics
echo -e "${YELLOW}Step 7: Creating Kafka topics...${NC}"
kubectl exec -n aurora-logs kafka-0 -- kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic aurora-logs-error \
    --partitions 10 \
    --replication-factor 1 || true

kubectl exec -n aurora-logs kafka-0 -- kafka-topics.sh \
    --bootstrap-server localhost:9092 \
    --create --if-not-exists \
    --topic aurora-logs-slowquery \
    --partitions 10 \
    --replication-factor 1 || true
echo ""

# Step 8: Deploy Discovery and Processor services
echo -e "${YELLOW}Step 8: Deploying Discovery and Processor Services...${NC}"
wait_for_deployment "discovery" "aurora-logs"
wait_for_deployment "processor" "aurora-logs"
echo ""

# Step 9: Apply Network Policies
echo -e "${YELLOW}Step 9: Applying Network Policies...${NC}"
kubectl apply -f 06-network-policies.yaml
echo ""

# Step 10: Apply Autoscaling
echo -e "${YELLOW}Step 10: Configuring Autoscaling...${NC}"
kubectl apply -f 05-autoscaling.yaml
echo ""

# Show deployment status
echo -e "${YELLOW}=== Deployment Status ===${NC}"
echo ""

echo "Pods:"
kubectl get pods -n aurora-logs -o wide
echo ""

echo "Services:"
kubectl get services -n aurora-logs
echo ""

echo "Deployments:"
kubectl get deployments -n aurora-logs
echo ""

# Check for any pods not running
NOT_RUNNING=$(kubectl get pods -n aurora-logs --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [ "$NOT_RUNNING" -gt 0 ]; then
    echo -e "${YELLOW}Warning: Some pods are not in Running state${NC}"
    kubectl get pods -n aurora-logs --field-selector=status.phase!=Running
    echo ""
fi

# Show access information
echo -e "${GREEN}=== Access Information ===${NC}"
echo ""
echo "OpenObserve UI:"
echo "  Internal: http://openobserve-service.aurora-logs.svc.cluster.local:5080"
echo "  Credentials: admin@example.com / Complexpass#123"
echo ""
echo "Kafka Brokers:"
echo "  kafka-service.aurora-logs.svc.cluster.local:9092"
echo ""
echo "Valkey/Redis:"
echo "  valkey-service.aurora-logs.svc.cluster.local:6379"
echo ""

# Show logs command
echo -e "${YELLOW}=== Useful Commands ===${NC}"
echo ""
echo "View logs:"
echo "  kubectl logs -n aurora-logs -l app=discovery -f"
echo "  kubectl logs -n aurora-logs -l app=processor -f"
echo ""
echo "Check Kafka topics:"
echo "  kubectl exec -n aurora-logs kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --list"
echo ""
echo "Check consumer lag:"
echo "  kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh --bootstrap-server localhost:9092 --group aurora-processor-group --describe"
echo ""

echo -e "${GREEN}Deployment complete!${NC}"