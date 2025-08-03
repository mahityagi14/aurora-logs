#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Aurora Log System - Status Check ==="
echo ""

# Function to check deployment status
check_deployment() {
    local deployment=$1
    local namespace=$2
    local ready=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired=$(kubectl get deployment $deployment -n $namespace -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$ready" == "$desired" ] && [ "$ready" != "0" ]; then
        echo -e "$deployment: ${GREEN}✓ Ready ($ready/$desired)${NC}"
    else
        echo -e "$deployment: ${RED}✗ Not Ready ($ready/$desired)${NC}"
    fi
}

# Check namespace
if kubectl get namespace aurora-logs &>/dev/null; then
    echo -e "Namespace: ${GREEN}✓ aurora-logs exists${NC}"
else
    echo -e "Namespace: ${RED}✗ aurora-logs not found${NC}"
    exit 1
fi
echo ""

# Check deployments
echo "Deployments:"
check_deployment "valkey" "aurora-logs"
check_deployment "kafka" "aurora-logs"
check_deployment "openobserve" "aurora-logs"
check_deployment "discovery" "aurora-logs"
check_deployment "processor" "aurora-logs"
echo ""

# Check pods
echo "Pod Status:"
kubectl get pods -n aurora-logs -o wide
echo ""

# Check services
echo "Services:"
kubectl get services -n aurora-logs
echo ""

# Check Kafka topics
echo "Kafka Topics:"
kubectl exec -n aurora-logs kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null || echo "Unable to list topics"
echo ""

# Check consumer groups
echo "Kafka Consumer Groups:"
kubectl exec -n aurora-logs kafka-0 -- kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list 2>/dev/null || echo "Unable to list consumer groups"
echo ""

# Check recent logs for errors
echo "Recent Errors (last 5 minutes):"
echo "Discovery:"
kubectl logs -n aurora-logs -l app=discovery --since=5m 2>/dev/null | grep -i error | tail -5 || echo "  No recent errors"
echo ""
echo "Processor:"
kubectl logs -n aurora-logs -l app=processor --since=5m 2>/dev/null | grep -i error | tail -5 || echo "  No recent errors"
echo ""

# Resource usage
echo "Resource Usage:"
kubectl top pods -n aurora-logs 2>/dev/null || echo "Metrics server not available"
echo ""

# Check network policies
echo "Network Policies:"
kubectl get networkpolicy -n aurora-logs
echo ""

echo "=== End Status Check ==="