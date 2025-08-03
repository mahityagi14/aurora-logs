#!/bin/bash

# Aurora Log System - Health Check Script
# This script validates the health of all components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="aurora-logs"
FAILED=0

echo -e "${BLUE}=== Aurora Log System Health Check ===${NC}"
echo -e "${BLUE}Checking system health at $(date)${NC}\n"

# Function to check deployment
check_deployment() {
    local name=$1
    local min_replicas=${2:-1}
    
    echo -n "Checking $name deployment... "
    
    # Check if deployment exists
    if ! kubectl get deployment $name -n $NAMESPACE &> /dev/null; then
        echo -e "${RED}NOT FOUND${NC}"
        ((FAILED++))
        return
    fi
    
    # Check replicas
    READY=$(kubectl get deployment $name -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment $name -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [ "$READY" -ge "$min_replicas" ] && [ "$READY" -eq "$DESIRED" ]; then
        echo -e "${GREEN}HEALTHY${NC} ($READY/$DESIRED replicas ready)"
    else
        echo -e "${RED}UNHEALTHY${NC} ($READY/$DESIRED replicas ready)"
        ((FAILED++))
    fi
}

# Function to check pod logs for errors
check_pod_logs() {
    local app_label=$1
    local error_count=0
    
    echo -n "Checking $app_label logs for errors... "
    
    # Get pod name
    POD=$(kubectl get pods -n $NAMESPACE -l app=$app_label -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$POD" ]; then
        echo -e "${YELLOW}NO POD FOUND${NC}"
        return
    fi
    
    # Check for error logs in last 100 lines
    error_count=$(kubectl logs $POD -n $NAMESPACE --tail=100 2>/dev/null | grep -iE "error|fatal|panic" | wc -l || echo "0")
    
    if [ "$error_count" -eq "0" ]; then
        echo -e "${GREEN}CLEAN${NC}"
    else
        echo -e "${YELLOW}WARNINGS${NC} ($error_count error lines in recent logs)"
    fi
}

# Function to check service connectivity
check_service() {
    local service=$1
    local port=$2
    
    echo -n "Checking $service service connectivity... "
    
    # Check if service exists
    if ! kubectl get svc $service -n $NAMESPACE &> /dev/null; then
        echo -e "${RED}NOT FOUND${NC}"
        ((FAILED++))
        return
    fi
    
    # Get service endpoint
    ENDPOINT=$(kubectl get endpoints $service -n $NAMESPACE -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
    
    if [ -n "$ENDPOINT" ]; then
        echo -e "${GREEN}READY${NC} (endpoint: $ENDPOINT:$port)"
    else
        echo -e "${RED}NO ENDPOINTS${NC}"
        ((FAILED++))
    fi
}

# Check namespace
echo -e "${BLUE}1. Checking namespace...${NC}"
if kubectl get namespace $NAMESPACE &> /dev/null; then
    echo -e "Namespace '$NAMESPACE': ${GREEN}EXISTS${NC}"
else
    echo -e "Namespace '$NAMESPACE': ${RED}NOT FOUND${NC}"
    exit 1
fi

# Check deployments
echo -e "\n${BLUE}2. Checking deployments...${NC}"
check_deployment "discovery" 1
check_deployment "processor" 1
check_deployment "kafka" 1
check_deployment "openobserve" 1
check_deployment "valkey" 1

# Check services
echo -e "\n${BLUE}3. Checking services...${NC}"
check_service "kafka-service" 9092
check_service "openobserve-service" 5080
check_service "valkey-service" 6379

# Check PVCs
echo -e "\n${BLUE}4. Checking persistent volumes...${NC}"
for pvc in kafka-data-pvc openobserve-data-pvc; do
    echo -n "Checking PVC $pvc... "
    STATUS=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$STATUS" == "Bound" ]; then
        echo -e "${GREEN}BOUND${NC}"
    else
        echo -e "${RED}$STATUS${NC}"
        ((FAILED++))
    fi
done

# Check secrets
echo -e "\n${BLUE}5. Checking secrets...${NC}"
for secret in app-secrets openobserve-credentials openobserve-secret; do
    echo -n "Checking secret $secret... "
    if kubectl get secret $secret -n $NAMESPACE &> /dev/null; then
        echo -e "${GREEN}EXISTS${NC}"
    else
        echo -e "${RED}NOT FOUND${NC}"
        ((FAILED++))
    fi
done

# Check ConfigMaps
echo -e "\n${BLUE}6. Checking configmaps...${NC}"
echo -n "Checking configmap app-config... "
if kubectl get configmap app-config -n $NAMESPACE &> /dev/null; then
    echo -e "${GREEN}EXISTS${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
    ((FAILED++))
fi

# Check Kafka topic
echo -e "\n${BLUE}7. Checking Kafka...${NC}"
echo -n "Checking Kafka topic 'aurora-logs'... "
TOPIC_EXISTS=$(kubectl exec -n $NAMESPACE deployment/kafka -- kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | grep -c "aurora-logs" || echo "0")
if [ "$TOPIC_EXISTS" -eq "1" ]; then
    echo -e "${GREEN}EXISTS${NC}"
else
    echo -e "${RED}NOT FOUND${NC}"
    ((FAILED++))
fi

# Check pod logs
echo -e "\n${BLUE}8. Checking pod logs...${NC}"
check_pod_logs "discovery"
check_pod_logs "processor"
check_pod_logs "openobserve"

# Check HPA status
echo -e "\n${BLUE}9. Checking autoscaling...${NC}"
for hpa in discovery-hpa processor-hpa; do
    echo -n "Checking HPA $hpa... "
    if kubectl get hpa $hpa -n $NAMESPACE &> /dev/null; then
        CURRENT=$(kubectl get hpa $hpa -n $NAMESPACE -o jsonpath='{.status.currentReplicas}' 2>/dev/null || echo "?")
        MIN=$(kubectl get hpa $hpa -n $NAMESPACE -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "?")
        MAX=$(kubectl get hpa $hpa -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "?")
        echo -e "${GREEN}ACTIVE${NC} (current: $CURRENT, min: $MIN, max: $MAX)"
    else
        echo -e "${RED}NOT FOUND${NC}"
        ((FAILED++))
    fi
done

# Check AWS connectivity (IAM roles)
echo -e "\n${BLUE}10. Checking AWS connectivity...${NC}"
for sa in discovery-sa processor-sa openobserve-sa; do
    echo -n "Checking service account $sa IAM annotation... "
    ROLE=$(kubectl get sa $sa -n $NAMESPACE -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null)
    if [ -n "$ROLE" ]; then
        echo -e "${GREEN}CONFIGURED${NC}"
    else
        echo -e "${YELLOW}NO IAM ROLE${NC}"
    fi
done

# Check OpenObserve ALB
echo -e "\n${BLUE}11. Checking OpenObserve access...${NC}"
ALB_DNS=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "")
if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
    echo -n "Checking OpenObserve ALB health... "
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 5 http://$ALB_DNS/ 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" =~ ^(200|301|302|307)$ ]]; then
        echo -e "${GREEN}ACCESSIBLE${NC} (HTTP $HTTP_CODE)"
    else
        echo -e "${RED}NOT ACCESSIBLE${NC} (HTTP $HTTP_CODE)"
        ((FAILED++))
    fi
else
    echo -e "OpenObserve ALB: ${YELLOW}NOT CONFIGURED${NC}"
fi

# Summary
echo -e "\n${BLUE}=== Health Check Summary ===${NC}"
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All health checks passed!${NC}"
    echo -e "\nSystem is healthy and ready for use."
else
    echo -e "${RED}✗ $FAILED health checks failed${NC}"
    echo -e "\nPlease review the issues above and run:"
    echo -e "  kubectl describe pods -n $NAMESPACE"
    echo -e "  kubectl logs -f deployment/<service-name> -n $NAMESPACE"
fi

# Show metrics
echo -e "\n${BLUE}Current resource usage:${NC}"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo -e "${YELLOW}Metrics server not available${NC}"

exit $FAILED