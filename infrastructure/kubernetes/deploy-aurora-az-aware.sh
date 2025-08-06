#!/bin/bash
set -e

echo "🚀 Deploying Aurora Log System (AZ-Aware)"
echo "=========================================="

NAMESPACE="aurora-logs"

# Check node AZ configuration
./check-node-az.sh
if [ $? -ne 0 ]; then
    echo "❌ AZ configuration check failed. Please resolve issues before deploying."
    exit 1
fi

# Function to wait for deployment
wait_for_deployment() {
    local name=$1
    local timeout=${2:-300}
    echo "⏳ Waiting for $name to be ready..."
    kubectl wait --for=condition=available --timeout=${timeout}s deployment/$name -n $NAMESPACE || true
}

# Function to add node affinity to deployments using PVCs
add_node_affinity() {
    local deployment=$1
    local az=$2
    
    echo "📍 Adding node affinity for $deployment to AZ: $az"
    
    # Patch deployment to add node affinity
    kubectl patch deployment $deployment -n $NAMESPACE --type=json -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/affinity",
        "value": {
          "nodeAffinity": {
            "requiredDuringSchedulingIgnoredDuringExecution": {
              "nodeSelectorTerms": [{
                "matchExpressions": [{
                  "key": "topology.kubernetes.io/zone",
                  "operator": "In",
                  "values": ["'$az'"]
                }]
              }]
            }
          }
        }
      }
    ]' 2>/dev/null || echo "Note: Could not add affinity to $deployment"
}

echo "📦 Creating namespace..."
kubectl apply -f 00-namespace.yaml

echo "🔐 Creating secrets..."
kubectl apply -f 01-secrets.yaml

echo "⚙️  Creating configmaps..."
kubectl apply -f 02-configmaps.yaml

echo "💾 Creating storage..."
# Check if we need AZ-aware storage
if [ -n "$NODE_AZ" ] && [ -z "$KAFKA_PVC_AZ" ]; then
    echo "   Using AZ-aware storage for: $NODE_AZ"
    kubectl apply -f 03-storage-az-aware.yaml
else
    kubectl apply -f 03-storage.yaml
fi

echo "🗄️  Deploying Valkey (Redis)..."
kubectl apply -f 04-valkey.yaml
wait_for_deployment valkey

echo "📨 Deploying Kafka..."
kubectl apply -f 05-kafka.yaml

# If single node, add affinity to Kafka
if [ -n "$NODE_AZ" ]; then
    add_node_affinity kafka $NODE_AZ
fi

wait_for_deployment kafka

echo "📊 Deploying OpenObserve..."
kubectl apply -f 06-openobserve.yaml

# If single node, add affinity to OpenObserve
if [ -n "$NODE_AZ" ]; then
    add_node_affinity openobserve $NODE_AZ
fi

wait_for_deployment openobserve

echo "🔍 Deploying Discovery service..."
kubectl apply -f 07-discovery.yaml
wait_for_deployment discovery

echo "⚡ Deploying Processor..."
kubectl apply -f 08-processor.yaml
wait_for_deployment processor

echo "🚦 Setting up autoscaling..."
kubectl apply -f 09-autoscaling.yaml

echo "🔒 Applying network policies..."
kubectl apply -f 10-network-policies.yaml

echo "📋 Applying pod policies..."
kubectl apply -f 11-policies.yaml

echo ""
echo "✅ Deployment completed successfully!"
echo "================================================"
echo ""
echo "🔍 Checking deployment status..."
kubectl get all -n $NAMESPACE

echo ""
echo "📊 Pod status:"
kubectl get pods -n $NAMESPACE -o wide

echo ""
echo "🌐 Service endpoints:"
echo "- OpenObserve: kubectl port-forward -n $NAMESPACE svc/openobserve-service 5080:5080"
echo "- Kafka: kubectl port-forward -n $NAMESPACE svc/kafka 9092:9092"
echo ""
echo "🔧 Registering OpenObserve with ALB..."
if [ -f "register-openobserve-alb.sh" ]; then
    ./register-openobserve-alb.sh
else
    echo "  ALB registration script not found. Run manually if needed."
fi

echo ""
echo "📈 To optimize kube-system resources for single-node cluster:"
echo "   ./optimize-kube-system.sh"