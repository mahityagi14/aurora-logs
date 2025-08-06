#!/bin/bash

echo "🧹 Cleaning Aurora Log System Deployment"
echo "========================================"

# Confirm cleanup
read -p "⚠️  This will delete all Aurora Log System resources. Are you sure? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo -e "\n🗑️  Deleting Aurora Log System resources..."

# Delete namespace (this will delete all resources within it)
echo "Deleting namespace aurora-logs..."
kubectl delete namespace aurora-logs --force --grace-period=0 2>/dev/null || true

# Clean up any remaining PVs
echo -e "\n🧹 Cleaning up persistent volumes..."
kubectl get pv | grep aurora | awk '{print $1}' | xargs -r kubectl delete pv --force --grace-period=0 2>/dev/null || true

echo -e "\n✅ Cleanup complete!"