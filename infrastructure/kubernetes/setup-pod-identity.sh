#!/bin/bash
# Setup EKS Pod Identity for Aurora Log System
# This replaces IRSA/OIDC configuration

set -e

# Configuration
AWS_ACCOUNT_ID="072006186126"
AWS_REGION="us-east-1"
CLUSTER_NAME="aurora-logs-poc-cluster"
NAMESPACE="aurora-logs"

echo "Setting up EKS Pod Identity associations..."

# Create Pod Identity associations
echo "Creating Pod Identity association for discovery-sa..."
aws eks create-pod-identity-association \
  --cluster-name $CLUSTER_NAME \
  --namespace $NAMESPACE \
  --service-account discovery-sa \
  --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/aurora-logs-poc-discovery-role \
  --region $AWS_REGION \
  2>/dev/null || echo "Association already exists"

echo "Creating Pod Identity association for processor-sa..."
aws eks create-pod-identity-association \
  --cluster-name $CLUSTER_NAME \
  --namespace $NAMESPACE \
  --service-account processor-sa \
  --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/aurora-logs-poc-processor-role \
  --region $AWS_REGION \
  2>/dev/null || echo "Association already exists"

echo "Creating Pod Identity association for openobserve-sa..."
aws eks create-pod-identity-association \
  --cluster-name $CLUSTER_NAME \
  --namespace $NAMESPACE \
  --service-account openobserve-sa \
  --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/aurora-logs-poc-openobserve-role \
  --region $AWS_REGION \
  2>/dev/null || echo "Association already exists"

# List associations
echo ""
echo "Current Pod Identity associations:"
aws eks list-pod-identity-associations \
  --cluster-name $CLUSTER_NAME \
  --region $AWS_REGION \
  --output table

echo ""
echo "Pod Identity setup complete!"
echo "Note: Pods must be restarted to use the new identity associations."