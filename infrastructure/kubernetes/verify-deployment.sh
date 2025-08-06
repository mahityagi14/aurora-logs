#!/bin/bash
set -e

NAMESPACE="aurora-logs"

echo "🔍 Verifying Aurora Log System Deployment"
echo "========================================"

# Check namespace
echo "✓ Checking namespace..."
kubectl get namespace $NAMESPACE

# Check all pods are running
echo -e "\n✓ Checking pod status..."
kubectl get pods -n $NAMESPACE

# Check services
echo -e "\n✓ Checking services..."
kubectl get svc -n $NAMESPACE

# Check PVCs
echo -e "\n✓ Checking persistent volumes..."
kubectl get pvc -n $NAMESPACE

# Check ConfigMaps and Secrets
echo -e "\n✓ Checking configurations..."
kubectl get configmap,secret -n $NAMESPACE

# Check HPA
echo -e "\n✓ Checking autoscaling..."
kubectl get hpa -n $NAMESPACE

# Test OpenObserve connectivity
echo -e "\n✓ Testing OpenObserve..."
kubectl exec -n $NAMESPACE deployment/processor -- wget -q -O- http://openobserve-service:5080/healthz || echo "OpenObserve health check failed"

# Test Kafka connectivity
echo -e "\n✓ Testing Kafka..."
kubectl exec -n $NAMESPACE deployment/processor -- nc -zv kafka 9092 || echo "Kafka connectivity check failed"

# Check logs for errors
echo -e "\n✓ Checking for errors in logs..."
for pod in discovery processor openobserve kafka valkey; do
    echo "Checking $pod..."
    kubectl logs -n $NAMESPACE -l app=$pod --tail=10 | grep -i error || echo "No errors found in $pod"
done

echo -e "\n✅ Deployment verification complete!"