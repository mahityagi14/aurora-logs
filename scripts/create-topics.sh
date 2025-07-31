#!/bin/bash
set -e

# Script to create Kafka topics for Aurora Log System

NAMESPACE=${NAMESPACE:-aurora-logs}
KAFKA_POD=${KAFKA_POD:-kafka-0}
PARTITIONS=${PARTITIONS:-10}
REPLICATION_FACTOR=${REPLICATION_FACTOR:-3}

echo "Creating Kafka topics in namespace: $NAMESPACE"

# Wait for Kafka to be ready
echo "Waiting for Kafka to be ready..."
kubectl wait --for=condition=ready pod/$KAFKA_POD -n $NAMESPACE --timeout=300s

# Function to create topic
create_topic() {
    local topic=$1
    local retention_ms=${2:-604800000}  # Default 7 days
    
    echo "Creating topic: $topic"
    kubectl exec -n $NAMESPACE $KAFKA_POD -- kafka-topics.sh \
        --create \
        --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic $topic \
        --partitions $PARTITIONS \
        --replication-factor $REPLICATION_FACTOR \
        --config retention.ms=$retention_ms \
        --config compression.type=snappy \
        --config max.message.bytes=10485760
}

# Create topics
create_topic "aurora-logs-error" 604800000      # 7 days retention
create_topic "aurora-logs-slowquery" 2592000000 # 30 days retention
create_topic "aurora-logs-dlq" 1209600000       # 14 days retention for dead letter queue

# List topics
echo ""
echo "Listing all topics:"
kubectl exec -n $NAMESPACE $KAFKA_POD -- kafka-topics.sh \
    --list \
    --bootstrap-server localhost:9092

echo ""
echo "Topic creation completed!"