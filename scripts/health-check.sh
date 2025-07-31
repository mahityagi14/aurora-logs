#!/bin/bash
set -e

# Health check script for Aurora Log System

NAMESPACE=${NAMESPACE:-aurora-logs}
TIMEOUT=${TIMEOUT:-30}

echo "Checking Aurora Log System health in namespace: $NAMESPACE"

# Function to check deployment status
check_deployment() {
    local deployment=$1
    local replicas=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    local desired=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    
    if [ "$replicas" == "$desired" ] && [ "$replicas" -gt 0 ]; then
        echo "✓ $deployment: $replicas/$desired replicas ready"
        return 0
    else
        echo "✗ $deployment: $replicas/$desired replicas ready"
        return 1
    fi
}

# Function to check statefulset status
check_statefulset() {
    local statefulset=$1
    local replicas=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
    local desired=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    
    if [ "$replicas" == "$desired" ] && [ "$replicas" -gt 0 ]; then
        echo "✓ $statefulset: $replicas/$desired replicas ready"
        return 0
    else
        echo "✗ $statefulset: $replicas/$desired replicas ready"
        return 1
    fi
}

# Function to check service endpoints
check_service() {
    local service=$1
    local endpoints=$(kubectl get endpoints $service -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
    
    if [ "$endpoints" -gt 0 ]; then
        echo "✓ $service: $endpoints endpoints available"
        return 0
    else
        echo "✗ $service: No endpoints available"
        return 1
    fi
}

# Check all components
echo ""
echo "Checking Deployments..."
check_deployment "discovery" || exit 1
check_deployment "processor" || exit 1
check_deployment "openobserve" || exit 1

echo ""
echo "Checking StatefulSets..."
check_statefulset "kafka" || exit 1
check_statefulset "valkey" || exit 1

echo ""
echo "Checking Services..."
check_service "discovery-service" || exit 1
check_service "processor-service" || exit 1
check_service "kafka-service" || exit 1
check_service "openobserve-service" || exit 1

echo ""
echo "Checking Kafka Topics..."
topics=$(kubectl exec -n $NAMESPACE kafka-0 -- kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -E "aurora-logs-(error|slowquery)" | wc -l)
if [ "$topics" -ge 2 ]; then
    echo "✓ Kafka topics: Found $topics aurora-logs topics"
else
    echo "✗ Kafka topics: Expected 2 topics, found $topics"
    exit 1
fi

echo ""
echo "Checking PersistentVolumeClaims..."
pvcs=$(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' | wc -w)
echo "✓ PVCs: $pvcs volumes bound"

echo ""
echo "Checking Ingress..."
ingress_host=$(kubectl get ingress openobserve-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
if [ -n "$ingress_host" ]; then
    echo "✓ Ingress: Available at $ingress_host"
else
    echo "⚠ Ingress: No load balancer hostname assigned yet"
fi

echo ""
echo "Health check completed successfully!"