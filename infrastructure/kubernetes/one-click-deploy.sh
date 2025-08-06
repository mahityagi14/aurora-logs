#!/bin/bash
set -e

echo "🚀 One-Click Aurora Log System Deployment"
echo "========================================"

# Check prerequisites
echo "📋 Checking prerequisites..."

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster. Please configure kubectl."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Setup IAM permissions
echo -e "\n🔐 Setting up IAM permissions..."
if [ -f "./setup-iam-permissions.sh" ]; then
    ./setup-iam-permissions.sh
else
    echo "⚠️  IAM setup script not found. Please ensure IAM permissions are configured manually."
fi

# Deploy
echo -e "\n🚀 Starting deployment..."

# Check if AZ-aware deployment script exists
if [ -f "./deploy-aurora-az-aware.sh" ]; then
    echo "Using AZ-aware deployment..."
    ./deploy-aurora-az-aware.sh
else
    echo "Using standard deployment..."
    ./deploy-aurora.sh
fi


# Wait for all pods to be ready
echo -e "\n⏳ Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n aurora-logs --timeout=600s || true

# Initialize OpenObserve streams
echo -e "\n📊 Initializing OpenObserve streams..."
if [ -f "./init-openobserve-streams.sh" ]; then
    ./init-openobserve-streams.sh
else
    echo "⚠️  Stream initialization script not found. Streams will be created on first data push."
fi

# Register ALB
echo -e "\n🔗 Registering OpenObserve with ALB..."
if [ -f "./register-openobserve-alb.sh" ]; then
    ./register-openobserve-alb.sh
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "")
    
    if [ -n "$ALB_DNS" ]; then
        echo -e "\n✅ ALB Registration successful!"
        echo "OpenObserve is accessible at: http://$ALB_DNS"
    else
        echo -e "\n⚠️  ALB registration completed but DNS not found"
    fi
else
    echo "⚠️  ALB registration script not found. Skipping ALB setup."
fi

# Run verification
echo -e "\n🔍 Running deployment verification..."
./verify-deployment.sh

# Show access info
echo -e "\n📌 Access Information:"
echo "========================================"
ALB_DNS=$(aws elbv2 describe-load-balancers --names openobserve-alb --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "ALB not found")
echo "OpenObserve URL: http://$ALB_DNS"
echo "Username: admin@example.com"
echo "Password: Complexpass#123"
echo ""
echo "Port forwarding (if ALB not available):"
echo "kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080"

echo -e "\n✅ Deployment complete!"