#!/bin/bash
set -e

# Aurora Log System Test Suite

echo "====================================="
echo "Aurora Log System - Test Suite"
echo "====================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test configuration
NAMESPACE=${NAMESPACE:-aurora-logs}
TEST_TIMEOUT=${TEST_TIMEOUT:-300}
LOAD_TEST_DURATION=${LOAD_TEST_DURATION:-60}

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ $2${NC}"
    else
        echo -e "${RED}✗ $2${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Initialize test counter
FAILED_TESTS=0

echo "1. Pre-deployment Checks"
echo "------------------------"

# Check K8s connectivity
echo -n "Checking Kubernetes connectivity... "
kubectl version --short &>/dev/null
print_result $? "Kubernetes connected"

# Check required namespaces
echo -n "Checking namespaces... "
kubectl get namespace $NAMESPACE &>/dev/null
print_result $? "Namespace $NAMESPACE exists"

echo ""
echo "2. Service Health Checks"
echo "------------------------"

# Check deployments
for deployment in discovery processor openobserve; do
    echo -n "Checking $deployment deployment... "
    READY=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [ "$READY" -eq "$DESIRED" ] && [ "$READY" -gt 0 ]; then
        print_result 0 "$deployment: $READY/$DESIRED replicas ready"
    else
        print_result 1 "$deployment: $READY/$DESIRED replicas ready"
    fi
done

# Check StatefulSets
for statefulset in kafka valkey; do
    echo -n "Checking $statefulset statefulset... "
    READY=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    DESIRED=$(kubectl get statefulset $statefulset -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    if [ "$READY" -eq "$DESIRED" ] && [ "$READY" -gt 0 ]; then
        print_result 0 "$statefulset: $READY/$DESIRED replicas ready"
    else
        print_result 1 "$statefulset: $READY/$DESIRED replicas ready"
    fi
done

echo ""
echo "3. Kafka Topic Validation"
echo "-------------------------"

# Check Kafka topics
KAFKA_POD=$(kubectl get pods -n $NAMESPACE -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$KAFKA_POD" ]; then
    echo -n "Listing Kafka topics... "
    TOPICS=$(kubectl exec -n $NAMESPACE $KAFKA_POD -- kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep aurora-logs | wc -l)
    if [ "$TOPICS" -ge 2 ]; then
        print_result 0 "Found $TOPICS aurora-logs topics"
    else
        print_result 1 "Expected 2+ topics, found $TOPICS"
    fi
else
    print_result 1 "Kafka pod not found"
fi

echo ""
echo "4. Valkey Cache Testing"
echo "-----------------------"

# Test Valkey connectivity
VALKEY_POD=$(kubectl get pods -n $NAMESPACE -l app=valkey -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$VALKEY_POD" ]; then
    echo -n "Testing Valkey connectivity... "
    kubectl exec -n $NAMESPACE $VALKEY_POD -- valkey-cli ping &>/dev/null
    print_result $? "Valkey responding to ping"
    
    echo -n "Testing Valkey operations... "
    kubectl exec -n $NAMESPACE $VALKEY_POD -- valkey-cli SET test:key "test-value" EX 60 &>/dev/null
    VALUE=$(kubectl exec -n $NAMESPACE $VALKEY_POD -- valkey-cli GET test:key 2>/dev/null)
    if [ "$VALUE" = "test-value" ]; then
        print_result 0 "Valkey read/write working"
    else
        print_result 1 "Valkey read/write failed"
    fi
else
    print_result 1 "Valkey pod not found"
fi

echo ""
echo "5. API Endpoint Testing"
echo "-----------------------"

# Test discovery service health
DISCOVERY_POD=$(kubectl get pods -n $NAMESPACE -l app=discovery -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$DISCOVERY_POD" ]; then
    echo -n "Testing discovery health endpoint... "
    kubectl exec -n $NAMESPACE $DISCOVERY_POD -- wget -q -O- http://localhost:8080/health &>/dev/null
    print_result $? "Discovery health endpoint responding"
fi

# Test processor service health
PROCESSOR_POD=$(kubectl get pods -n $NAMESPACE -l app=processor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$PROCESSOR_POD" ]; then
    echo -n "Testing processor health endpoint... "
    kubectl exec -n $NAMESPACE $PROCESSOR_POD -- wget -q -O- http://localhost:8080/health &>/dev/null
    print_result $? "Processor health endpoint responding"
    
fi

echo ""
echo "6. Log Processing Flow Test"
echo "---------------------------"

# Create test message
echo -n "Sending test log message to Kafka... "
TEST_MESSAGE='{
  "instance_id": "test-instance-001",
  "cluster_id": "test-cluster",
  "engine": "aurora-mysql",
  "log_type": "error",
  "log_file_name": "error/mysql-error-test.log",
  "last_written": '$(date +%s)',
  "size": 1024,
  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
}'

# Send to Kafka
if [ -n "$KAFKA_POD" ]; then
    echo "$TEST_MESSAGE" | kubectl exec -i -n $NAMESPACE $KAFKA_POD -- kafka-console-producer.sh \
        --broker-list localhost:9092 \
        --topic aurora-logs-error &>/dev/null
    print_result $? "Test message sent to Kafka"
    
    # Wait for processing
    echo -n "Waiting for message processing... "
    sleep 5
    
    # Check if message was consumed
    CONSUMER_LAG=$(kubectl exec -n $NAMESPACE $KAFKA_POD -- kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group aurora-processor-group \
        --describe 2>/dev/null | grep aurora-logs-error | awk '{print $5}' | head -1)
    
    if [ "$CONSUMER_LAG" = "0" ] || [ -z "$CONSUMER_LAG" ]; then
        print_result 0 "Message consumed successfully"
    else
        print_result 1 "Consumer lag: $CONSUMER_LAG"
    fi
fi

echo ""
echo "7. Security Scanning"
echo "--------------------"

# Check security contexts
echo -n "Verifying non-root containers... "
ROOT_CONTAINERS=$(kubectl get pods -n $NAMESPACE -o json | \
    jq -r '.items[].spec.containers[] | select(.securityContext.runAsNonRoot != true) | .name' | wc -l)
if [ "$ROOT_CONTAINERS" -eq 0 ]; then
    print_result 0 "All containers running as non-root"
else
    print_result 1 "$ROOT_CONTAINERS containers running as root"
fi

# Check resource limits
echo -n "Verifying resource limits... "
NO_LIMITS=$(kubectl get pods -n $NAMESPACE -o json | \
    jq -r '.items[].spec.containers[] | select(.resources.limits == null) | .name' | wc -l)
if [ "$NO_LIMITS" -eq 0 ]; then
    print_result 0 "All containers have resource limits"
else
    print_result 1 "$NO_LIMITS containers without limits"
fi

echo ""
echo "8. Performance Test"
echo "-------------------"

if [ "$RUN_PERF_TEST" = "true" ]; then
    echo "Running performance test for $LOAD_TEST_DURATION seconds..."
    
    # Generate load
    START_TIME=$(date +%s)
    MESSAGE_COUNT=0
    
    while [ $(($(date +%s) - START_TIME)) -lt $LOAD_TEST_DURATION ]; do
        for i in {1..10}; do
            TEST_MSG='{
              "instance_id": "perf-test-'$i'",
              "cluster_id": "perf-cluster",
              "engine": "aurora-mysql",
              "log_type": "error",
              "log_file_name": "error/perf-test-'$i'.log",
              "last_written": '$(date +%s)',
              "size": '$((RANDOM % 10000 + 1000))',
              "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
            }'
            
            echo "$TEST_MSG" | kubectl exec -i -n $NAMESPACE $KAFKA_POD -- \
                kafka-console-producer.sh --broker-list localhost:9092 --topic aurora-logs-error &>/dev/null
            
            MESSAGE_COUNT=$((MESSAGE_COUNT + 1))
        done
        sleep 1
    done
    
    ELAPSED=$(($(date +%s) - START_TIME))
    RATE=$((MESSAGE_COUNT / ELAPSED))
    echo "Sent $MESSAGE_COUNT messages in $ELAPSED seconds ($RATE msg/sec)"
    
    # Check processing lag
    sleep 10
    FINAL_LAG=$(kubectl exec -n $NAMESPACE $KAFKA_POD -- kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group aurora-processor-group \
        --describe 2>/dev/null | grep aurora-logs-error | awk '{print $5}' | head -1)
    
    if [ "$FINAL_LAG" = "0" ] || [ -z "$FINAL_LAG" ]; then
        print_result 0 "All messages processed (lag: 0)"
    else
        print_result 1 "Processing lag: $FINAL_LAG messages"
    fi
else
    echo -e "${YELLOW}Skipping performance test (set RUN_PERF_TEST=true to enable)${NC}"
fi

echo ""
echo "9. Cost Optimization Validation"
echo "-------------------------------"

# Check Spot instances
echo -n "Checking for Spot instance usage... "
SPOT_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."karpenter.sh/capacity-type" == "spot") | .metadata.name' | wc -l)
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
if [ "$SPOT_NODES" -gt 0 ]; then
    SPOT_PERCENT=$((SPOT_NODES * 100 / TOTAL_NODES))
    print_result 0 "Using $SPOT_NODES/$TOTAL_NODES Spot nodes ($SPOT_PERCENT%)"
else
    print_result 1 "No Spot instances found"
fi

# Check ARM64 nodes
echo -n "Checking for ARM64/Graviton usage... "
ARM_NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.nodeInfo.architecture == "arm64") | .metadata.name' | wc -l)
if [ "$ARM_NODES" -gt 0 ]; then
    ARM_PERCENT=$((ARM_NODES * 100 / TOTAL_NODES))
    print_result 0 "Using $ARM_NODES/$TOTAL_NODES ARM64 nodes ($ARM_PERCENT%)"
else
    print_result 1 "No ARM64 nodes found"
fi

echo ""
echo "10. Integration Test Summary"
echo "----------------------------"

# Run Go integration tests if available
if [ -f "integration_test.go" ]; then
    echo "Running Go integration tests..."
    go test -v -tags=integration -timeout 10m ./...
    print_result $? "Go integration tests"
else
    echo -e "${YELLOW}Go integration tests not found${NC}"
fi

echo ""
echo "====================================="
echo "Test Results Summary"
echo "====================================="
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}All tests passed! System is ready for production.${NC}"
    exit 0
else
    echo -e "${RED}$FAILED_TESTS tests failed. Please fix issues before production deployment.${NC}"
    exit 1
fi