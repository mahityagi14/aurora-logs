#!/bin/bash

echo "=== Aurora Log System - Complete Cleanup ==="
echo "This will remove all Aurora Log System resources from Kubernetes"
echo ""

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type=$1
    local namespace=$2
    local timeout=60
    local count=0
    
    echo "Waiting for all $resource_type to be deleted..."
    while [ $count -lt $timeout ]; do
        if ! kubectl get $resource_type -n $namespace 2>/dev/null | grep -v "No resources found"; then
            echo "✓ All $resource_type deleted"
            return 0
        fi
        sleep 2
        count=$((count + 2))
    done
    echo "⚠ Timeout waiting for $resource_type deletion"
    return 1
}

# Delete all deployments
echo "1. Deleting deployments..."
kubectl delete deployment --all -n aurora-logs --ignore-not-found=true

# Delete all services
echo "2. Deleting services..."
kubectl delete service --all -n aurora-logs --ignore-not-found=true

# Delete all configmaps
echo "3. Deleting configmaps..."
kubectl delete configmap --all -n aurora-logs --ignore-not-found=true

# Delete all secrets
echo "4. Deleting secrets..."
kubectl delete secret --all -n aurora-logs --ignore-not-found=true

# Delete all network policies
echo "5. Deleting network policies..."
kubectl delete networkpolicy --all -n aurora-logs --ignore-not-found=true

# Delete all HPA
echo "6. Deleting horizontal pod autoscalers..."
kubectl delete hpa --all -n aurora-logs --ignore-not-found=true

# Delete all PVCs
echo "7. Deleting persistent volume claims..."
kubectl delete pvc --all -n aurora-logs --ignore-not-found=true

# Delete all jobs and cronjobs
echo "8. Deleting jobs and cronjobs..."
kubectl delete job --all -n aurora-logs --ignore-not-found=true
kubectl delete cronjob --all -n aurora-logs --ignore-not-found=true

# Wait for pods to terminate
echo "9. Waiting for all pods to terminate..."
wait_for_deletion "pods" "aurora-logs"

# Delete service accounts
echo "10. Deleting service accounts..."
kubectl delete serviceaccount --all -n aurora-logs --ignore-not-found=true

# Delete roles and rolebindings
echo "11. Deleting RBAC resources..."
kubectl delete role --all -n aurora-logs --ignore-not-found=true
kubectl delete rolebinding --all -n aurora-logs --ignore-not-found=true

# Finally, delete the namespace
echo "12. Deleting namespace..."
kubectl delete namespace aurora-logs --ignore-not-found=true

# Wait for namespace deletion
echo "Waiting for namespace deletion to complete..."
count=0
while kubectl get namespace aurora-logs 2>/dev/null; do
    if [ $count -gt 120 ]; then
        echo "⚠ Namespace deletion timeout. May need manual intervention."
        break
    fi
    sleep 2
    count=$((count + 2))
done

echo ""
echo "=== Cleanup Complete ==="
echo ""

# Show remaining resources (should be empty)
echo "Checking for any remaining resources:"
kubectl get all -n aurora-logs 2>/dev/null || echo "✓ Namespace aurora-logs successfully removed"

echo ""
echo "Ready for fresh deployment!"