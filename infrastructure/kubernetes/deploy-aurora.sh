#!/bin/bash
set -e

echo "🚀 Deploying Aurora Log System with OTEL on aurora-node-2"
echo "================================================"

NAMESPACE="aurora-logs"

# Function to wait for deployment
wait_for_deployment() {
    local name=$1
    local timeout=${2:-300}
    echo "⏳ Waiting for $name to be ready..."
    kubectl wait --for=condition=available --timeout=${timeout}s deployment/$name -n $NAMESPACE
}

# Function to wait for daemonset
wait_for_daemonset() {
    local name=$1
    local timeout=${2:-300}
    echo "⏳ Waiting for $name daemonset to be ready..."
    kubectl wait --for=condition=ready pod -l app=$name -n $NAMESPACE --timeout=${timeout}s
}

# Function to check if resource exists
resource_exists() {
    kubectl get $1 $2 -n $NAMESPACE &> /dev/null
}

echo "📦 Creating namespace..."
kubectl apply -f 00-namespace.yaml

echo "🔐 Creating secrets..."
kubectl apply -f 01-secrets.yaml

echo "⚙️  Creating configmaps..."
kubectl apply -f 02-configmaps.yaml

echo "💾 Creating storage..."
kubectl apply -f 03-storage.yaml

echo "🗄️  Deploying Valkey (Redis)..."
kubectl apply -f 04-valkey.yaml
wait_for_deployment valkey

echo "📨 Deploying Kafka..."
kubectl apply -f 05-kafka.yaml
wait_for_deployment kafka

echo "📊 Deploying OpenObserve..."
kubectl apply -f 06-openobserve.yaml
wait_for_deployment openobserve

echo "🔍 Deploying Discovery service..."
kubectl apply -f 07-discovery.yaml
wait_for_deployment discovery

echo "⚡ Deploying Processor..."
kubectl apply -f 08-processor.yaml
wait_for_deployment processor-master

echo "🪶 Deploying Fluent Bit..."
kubectl apply -f 09-fluent-bit.yaml
wait_for_daemonset fluent-bit

echo "🚦 Setting up autoscaling..."
kubectl apply -f 10-autoscaling.yaml

echo "🔒 Applying network policies..."
kubectl apply -f 11-network-policies.yaml

echo "📋 Applying pod policies..."
kubectl apply -f 12-policies.yaml

echo "🔭 Deploying OTEL Collector..."
kubectl apply -f 13-otel.yaml
wait_for_deployment otel-collector

# Create Kafka topics
echo "📋 Creating Kafka topics..."
kubectl apply -f 05-kafka.yaml | grep -E "(Job|created)" || true

echo ""
echo "✅ Deployment completed successfully!"
echo "================================================"
echo ""
echo "🔍 Checking deployment status..."
kubectl get all -n $NAMESPACE

echo ""
echo "📊 Node assignment verification (should all be on aurora-node-2):"
kubectl get pods -n $NAMESPACE -o wide | grep -E "(NAME|Running)"

echo ""
echo "🌐 Service endpoints:"
echo "- OpenObserve: kubectl port-forward -n $NAMESPACE svc/openobserve-service 5080:5080"
echo "- OTEL Collector: kubectl port-forward -n $NAMESPACE svc/otel-collector 4317:4317"
echo "- Kafka: kubectl port-forward -n $NAMESPACE svc/kafka-service 9092:9092"
echo ""
echo "📈 OTEL is configured and ready to receive traces at otel-collector:4317"