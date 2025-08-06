#!/bin/bash

echo "🔄 Initializing OpenObserve streams..."

# Wait for OpenObserve to be ready
echo "⏳ Waiting for OpenObserve to be ready..."
kubectl wait --for=condition=ready pod -l app=openobserve -n aurora-logs --timeout=300s

# Get OpenObserve pod IP
OPENOBSERVE_POD=$(kubectl get pod -l app=openobserve -n aurora-logs -o jsonpath='{.items[0].metadata.name}')
OPENOBSERVE_IP=$(kubectl get pod $OPENOBSERVE_POD -n aurora-logs -o jsonpath='{.status.podIP}')

echo "📍 OpenObserve pod: $OPENOBSERVE_POD"
echo "📍 OpenObserve IP: $OPENOBSERVE_IP"

# Initialize streams by sending test data
echo "📝 Creating aurora_error_logs stream..."
kubectl exec -n aurora-logs $OPENOBSERVE_POD -- curl -s -X POST \
  "http://localhost:5080/api/default/aurora_error_logs/_json" \
  -u "admin@example.com:Complexpass#123" \
  -H "Content-Type: application/json" \
  -d '[{"_timestamp": '$(date +%s000)', "message": "Stream initialization", "level": "INFO"}]' \
  > /dev/null 2>&1

echo "📝 Creating aurora_slowquery_logs stream..."
kubectl exec -n aurora-logs $OPENOBSERVE_POD -- curl -s -X POST \
  "http://localhost:5080/api/default/aurora_slowquery_logs/_json" \
  -u "admin@example.com:Complexpass#123" \
  -H "Content-Type: application/json" \
  -d '[{"_timestamp": '$(date +%s000)', "message": "Stream initialization", "level": "INFO"}]' \
  > /dev/null 2>&1

echo "📝 Creating aurora_logs stream..."
kubectl exec -n aurora-logs $OPENOBSERVE_POD -- curl -s -X POST \
  "http://localhost:5080/api/default/aurora_logs/_json" \
  -u "admin@example.com:Complexpass#123" \
  -H "Content-Type: application/json" \
  -d '[{"_timestamp": '$(date +%s000)', "message": "Stream initialization", "level": "INFO"}]' \
  > /dev/null 2>&1

# Verify streams were created
echo -e "\n🔍 Verifying streams..."
kubectl exec -n aurora-logs $OPENOBSERVE_POD -- curl -s \
  "http://localhost:5080/api/default/streams" \
  -u "admin@example.com:Complexpass#123" | grep -E "(aurora_error_logs|aurora_slowquery_logs|aurora_logs)" | head -10

echo -e "\n✅ OpenObserve streams initialized"