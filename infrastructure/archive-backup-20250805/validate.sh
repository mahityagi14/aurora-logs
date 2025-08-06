#!/bin/bash

# Quick validation script to ensure deployment is working

set -e

NAMESPACE="aurora-logs"

echo "=== Quick Deployment Validation ==="
echo ""

# Check if all pods are running
echo "Checking pod status..."
PODS_NOT_RUNNING=$(kubectl get pods -n $NAMESPACE --no-headers | grep -v "Running" | wc -l)
if [ "$PODS_NOT_RUNNING" -eq "0" ]; then
    echo "✓ All pods are running"
else
    echo "✗ Some pods are not running:"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

# Check Kafka topic
echo ""
echo "Checking Kafka topic..."
if kubectl exec -n $NAMESPACE deployment/kafka -- kafka-topics --list --bootstrap-server localhost:9092 2>/dev/null | grep -q "aurora-logs"; then
    echo "✓ Kafka topic 'aurora-logs' exists"
else
    echo "✗ Kafka topic not found"
    exit 1
fi

# Check OpenObserve
echo ""
echo "Checking OpenObserve..."
OO_IP=$(kubectl get pod -n $NAMESPACE -l app=openobserve -o jsonpath='{.items[0].status.podIP}')
if [ -n "$OO_IP" ]; then
    echo "✓ OpenObserve pod IP: $OO_IP"
else
    echo "✗ OpenObserve pod not found"
    exit 1
fi

echo ""
echo "=== Deployment Validated Successfully ==="
echo ""
echo "Access OpenObserve:"
ALB_DNS=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "")
if [ -n "$ALB_DNS" ] && [ "$ALB_DNS" != "None" ]; then
    echo "URL: http://$ALB_DNS"
else
    echo "Use port-forward: kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080"
fi
echo "Username: admin@example.com"
echo "Password: Complexpass#123"