#!/bin/bash
set -e

echo "🧹 Cleaning up Aurora Log System deployment"
echo "=========================================="

NAMESPACE="aurora-logs"

echo "❌ Deleting all resources in namespace $NAMESPACE..."

# Delete in reverse order of creation
echo "📊 Deleting monitoring resources..."
kubectl delete -f 13-otel.yaml --ignore-not-found=true

echo "📋 Deleting policies..."
kubectl delete -f 12-policies.yaml --ignore-not-found=true
kubectl delete -f 11-network-policies.yaml --ignore-not-found=true
kubectl delete -f 10-autoscaling.yaml --ignore-not-found=true

echo "🔧 Deleting services..."
kubectl delete -f 08-processor.yaml --ignore-not-found=true
kubectl delete -f 07-discovery.yaml --ignore-not-found=true
kubectl delete -f 06-openobserve.yaml --ignore-not-found=true
kubectl delete -f 05-kafka.yaml --ignore-not-found=true
kubectl delete -f 04-valkey.yaml --ignore-not-found=true

echo "💾 Deleting storage..."
kubectl delete -f 03-storage.yaml --ignore-not-found=true

echo "🪶 Deleting Fluent Bit..."
kubectl delete -f 09-fluent-bit.yaml --ignore-not-found=true

echo "⚙️  Deleting configmaps..."
kubectl delete -f 02-configmaps.yaml --ignore-not-found=true

echo "🔐 Deleting secrets..."
kubectl delete -f 01-secrets.yaml --ignore-not-found=true

echo "📦 Deleting namespace..."
kubectl delete -f 00-namespace.yaml --ignore-not-found=true

echo ""
echo "✅ Cleanup completed!"
echo "=========================================="