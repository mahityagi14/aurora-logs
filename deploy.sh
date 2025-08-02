#!/bin/bash
set -e

# Aurora Log System Deployment Script

ENVIRONMENT=${1:-poc}
ACTION=${2:-apply}

echo "🚀 Deploying Aurora Log System - Environment: $ENVIRONMENT"

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl not found. Please install kubectl."
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI not found. Please install AWS CLI."
    exit 1
fi

# Check cluster access
echo "🔍 Checking cluster access..."
if ! kubectl get nodes &> /dev/null; then
    echo "❌ Cannot access Kubernetes cluster. Please configure kubectl."
    exit 1
fi

# Deploy based on action
case $ACTION in
    apply)
        echo "📦 Applying Kubernetes manifests..."
        kubectl apply -f infrastructure/kubernetes/01-namespace-rbac.yaml
        kubectl apply -f infrastructure/kubernetes/02-config-secrets.yaml
        kubectl apply -f infrastructure/kubernetes/03-services.yaml
        kubectl apply -f infrastructure/kubernetes/04-deployments.yaml
        kubectl apply -f infrastructure/kubernetes/05-autoscaling.yaml
        
        echo "✅ Deployment complete!"
        echo ""
        echo "📊 Check deployment status:"
        echo "kubectl get pods -n aurora-logs"
        echo ""
        echo "🌐 OpenObserve will be available at:"
        echo "http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com"
        ;;
        
    delete)
        echo "🗑️  Deleting Aurora Log System..."
        kubectl delete -f infrastructure/kubernetes/ --ignore-not-found=true
        echo "✅ Deletion complete!"
        ;;
        
    status)
        echo "📊 Current status:"
        kubectl get all -n aurora-logs
        ;;
        
    *)
        echo "Usage: $0 [poc|production] [apply|delete|status]"
        exit 1
        ;;
esac