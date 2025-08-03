#!/bin/bash

# Deploy Valkey to Kubernetes
echo "Deploying Valkey standalone instance..."

# Apply the Valkey deployment
kubectl apply -f 04-valkey.yaml

# Wait for deployment to be ready
echo "Waiting for Valkey to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/valkey -n aurora-logs

# Check the status
echo "Valkey deployment status:"
kubectl get deployment valkey -n aurora-logs
kubectl get service valkey-service -n aurora-logs
kubectl get pods -n aurora-logs -l app=valkey

# Test connectivity
echo "Testing Valkey connectivity..."
kubectl run -it --rm --restart=Never valkey-test --image=valkey/valkey:8.1.3 -n aurora-logs -- valkey-cli -h valkey-service ping

echo "Valkey deployment complete!"