#!/bin/bash
set -e

# Function to get node availability zone
get_node_az() {
    local node_name=$1
    kubectl get node $node_name -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/zone}' 2>/dev/null
}

# Function to check if PVC exists and get its AZ
get_pvc_az() {
    local pvc_name=$1
    local namespace=$2
    
    # Check if PVC exists
    if ! kubectl get pvc $pvc_name -n $namespace &>/dev/null; then
        echo ""
        return
    fi
    
    # Get the PV name
    local pv_name=$(kubectl get pvc $pvc_name -n $namespace -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    
    if [ -z "$pv_name" ]; then
        echo ""
        return
    fi
    
    # Get the AZ from PV
    kubectl get pv $pv_name -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null
}

# Main logic
echo "🔍 Checking Node Availability Zone Configuration"
echo "================================================"

# Get all nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')
NODE_COUNT=$(echo $NODES | wc -w)

if [ $NODE_COUNT -eq 0 ]; then
    echo "❌ No nodes found in cluster"
    exit 1
fi

echo "📍 Current cluster nodes:"
for node in $NODES; do
    AZ=$(get_node_az $node)
    echo "   - $node: $AZ"
done

# For single node cluster, get the AZ
if [ $NODE_COUNT -eq 1 ]; then
    NODE_AZ=$(get_node_az $NODES)
    echo ""
    echo "✅ Single node cluster detected in AZ: $NODE_AZ"
else
    # Multiple nodes - need to handle differently
    echo ""
    echo "⚠️  Multiple nodes detected. Storage will be created based on scheduler decision."
fi

# Check existing PVCs
echo ""
echo "📦 Checking existing PVCs in aurora-logs namespace:"

KAFKA_PVC_AZ=$(get_pvc_az "kafka-data-pvc" "aurora-logs")
OPENOBSERVE_PVC_AZ=$(get_pvc_az "openobserve-data-pvc" "aurora-logs")

if [ -n "$KAFKA_PVC_AZ" ]; then
    echo "   - kafka-data-pvc: $KAFKA_PVC_AZ"
fi

if [ -n "$OPENOBSERVE_PVC_AZ" ]; then
    echo "   - openobserve-data-pvc: $OPENOBSERVE_PVC_AZ"
fi

# Check for AZ mismatch
if [ $NODE_COUNT -eq 1 ] && [ -n "$KAFKA_PVC_AZ" ] && [ "$NODE_AZ" != "$KAFKA_PVC_AZ" ]; then
    echo ""
    echo "⚠️  WARNING: AZ Mismatch Detected!"
    echo "   Node is in: $NODE_AZ"
    echo "   PVCs are in: $KAFKA_PVC_AZ"
    echo ""
    echo "   This will prevent Kafka and OpenObserve from starting."
    echo "   Options:"
    echo "   1. Delete PVCs and redeploy (data loss)"
    echo "   2. Create node in $KAFKA_PVC_AZ"
    echo "   3. Use EFS storage (multi-AZ)"
    exit 1
fi

echo ""
echo "✅ AZ configuration check complete"

# Export for use in other scripts
export NODE_AZ
export KAFKA_PVC_AZ
export OPENOBSERVE_PVC_AZ