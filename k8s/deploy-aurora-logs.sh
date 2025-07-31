#!/bin/bash

# Aurora Log System Kubernetes Deployment Script
# This script deploys all components once kubectl authentication is fixed

set -e

echo "Aurora Log System - Kubernetes Deployment"
echo "========================================"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check authentication
echo "Checking Kubernetes authentication..."
if ! kubectl auth can-i get pods --namespace aurora-logs &> /dev/null; then
    echo "Error: Kubernetes authentication failed."
    echo "Please fix the authentication issue first. See kubernetes-auth-issue.md"
    exit 1
fi

# Function to wait for resource
wait_for_resource() {
    local resource=$1
    local namespace=$2
    local name=$3
    local timeout=${4:-300}
    
    echo "Waiting for $resource/$name in namespace $namespace..."
    kubectl wait --for=condition=ready $resource/$name -n $namespace --timeout=${timeout}s
}

# Step 1: Create namespaces and service accounts
echo "Step 1: Creating namespaces and service accounts..."
kubectl apply -f setup.yaml

# Step 2: Create ConfigMaps
echo "Step 2: Creating ConfigMaps..."
kubectl apply -f configmaps/

# Step 3: Create Secrets
echo "Step 3: Creating Secrets..."
# Update OpenObserve admin email before applying
sed -i "s/admin@yourcompany.com/${OPENOBSERVE_ADMIN_EMAIL:-admin@example.com}/g" values-poc.yaml
kubectl apply -f secrets/

# Step 4: Create Persistent Volume Claims
echo "Step 4: Creating Persistent Volume Claims..."
kubectl apply -f volumes/

# Step 5: Deploy Valkey (if using internal, otherwise skip)
if [ "${USE_EXTERNAL_VALKEY:-true}" = "false" ]; then
    echo "Step 5: Deploying Valkey..."
    kubectl apply -f deployments/valkey-deployment.yaml
    kubectl apply -f services/valkey-service.yaml
    wait_for_resource deployment aurora-logs valkey-deployment
else
    echo "Step 5: Skipping Valkey deployment (using external ElastiCache)"
fi

# Step 6: Deploy Kafka
echo "Step 6: Deploying Kafka..."
kubectl apply -f deployments/kafka-deployment.yaml
kubectl apply -f services/kafka-service.yaml
wait_for_resource deployment aurora-logs kafka-deployment

# Step 7: Deploy OpenObserve
echo "Step 7: Deploying OpenObserve..."
kubectl apply -f deployments/openobserve-deployment.yaml
kubectl apply -f services/openobserve-service.yaml
wait_for_resource deployment aurora-logs openobserve-deployment

# Step 8: Deploy Discovery Service
echo "Step 8: Deploying Discovery Service..."
kubectl apply -f deployments/discovery-deployment.yaml
wait_for_resource deployment aurora-logs discovery-deployment

# Step 9: Deploy Processor Service
echo "Step 9: Deploying Processor Service..."
kubectl apply -f deployments/processor-deployment.yaml
wait_for_resource deployment aurora-logs processor-deployment

# Step 10: Deploy Fluent Bit DaemonSet
echo "Step 10: Deploying Fluent Bit..."
kubectl apply -f daemonsets/fluent-bit-daemonset.yaml

# Step 11: Apply HPA (if enabled)
echo "Step 11: Applying Horizontal Pod Autoscalers..."
kubectl apply -f hpa/

# Step 12: Apply Pod Disruption Budgets
echo "Step 12: Applying Pod Disruption Budgets..."
kubectl apply -f poddisruptionbudgets/

# Step 13: Apply Cost Optimization (POC only)
echo "Step 13: Applying cost optimization configurations..."
kubectl apply -f cost-optimized/

# Step 14: Apply Security Policies
echo "Step 14: Applying security policies..."
kubectl apply -f security/

# Verify deployment
echo ""
echo "Deployment Status:"
echo "=================="
kubectl get all -n aurora-logs
kubectl get all -n fluent-bit

echo ""
echo "Service Endpoints:"
echo "=================="
kubectl get svc -n aurora-logs

echo ""
echo "To access OpenObserve UI (using NodePort):"
echo "1. Get any node IP: kubectl get nodes -o wide"
echo "2. Access: http://<NODE_IP>:30080"
echo ""
echo "To use port-forward instead:"
echo "kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080"
echo "Then access: http://localhost:5080"

echo ""
echo "Deployment complete!"