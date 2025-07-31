#!/bin/bash
set -e

# Script to apply K8s manifests with proper value substitution
# Usage: ./apply-with-values.sh values.yaml

if [ $# -ne 1 ]; then
    echo "Usage: $0 <values-file>"
    echo "Example: $0 values.yaml"
    exit 1
fi

VALUES_FILE=$1

if [ ! -f "$VALUES_FILE" ]; then
    echo "Error: Values file '$VALUES_FILE' not found"
    exit 1
fi

# Parse values from YAML file
AWS_REGION=$(yq eval '.awsRegion' "$VALUES_FILE")
AWS_ACCOUNT_ID=$(yq eval '.awsAccountId' "$VALUES_FILE")
ECR_REGISTRY=$(yq eval '.ecrRegistry' "$VALUES_FILE")
CACHE_ID=$(yq eval '.elasticacheCacheId' "$VALUES_FILE")
S3_BUCKET=$(yq eval '.s3BucketName' "$VALUES_FILE")
CERT_ARN=$(yq eval '.ingressCertificateArn' "$VALUES_FILE")
SECURITY_GROUP=$(yq eval '.ingressSecurityGroup' "$VALUES_FILE")

echo "Applying K8s manifests with values from $VALUES_FILE"
echo "AWS Region: $AWS_REGION"
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Create namespace and service accounts
kubectl apply -f setup.yaml

# Apply ConfigMaps with substitution
sed -e "s/\[region\]/$AWS_REGION/g" \
    -e "s/\[cache-id\]/$CACHE_ID/g" \
    configmaps/app-config.yaml | kubectl apply -f -

kubectl apply -f configmaps/fluent-bit-config.yaml

# Apply Services
kubectl apply -f services/

# Apply Deployments with substitution
for deployment in deployments/*.yaml; do
    sed -e "s/\[account-id\]/$AWS_ACCOUNT_ID/g" \
        -e "s/\[region\]/$AWS_REGION/g" \
        "$deployment" | kubectl apply -f -
done

# Apply DaemonSets
kubectl apply -f daemonsets/

# Apply Ingress with substitution
sed -e "s|arn:aws:acm:\[region\]:\[account-id\]:certificate/\[certificate-id\]|$CERT_ARN|g" \
    -e "s/alb-sg/$SECURITY_GROUP/g" \
    ingress/openobserve-ingress.yaml | kubectl apply -f -

echo "All manifests applied successfully!"
echo ""
echo "Don't forget to:"
echo "1. Create and apply the openobserve-secret.yaml with actual credentials"
echo "2. Update RBAC permissions as needed"
echo "3. Configure PersistentVolumes for production use"