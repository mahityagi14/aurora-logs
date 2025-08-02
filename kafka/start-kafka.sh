#!/bin/bash
set -e

echo "Starting Confluent Kafka in KRaft mode..."

# Set default values
export KAFKA_NODE_ID=${KAFKA_NODE_ID:-1}
export KAFKA_LISTENERS=${KAFKA_LISTENERS:-"PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"}
export KAFKA_ADVERTISED_LISTENERS=${KAFKA_ADVERTISED_LISTENERS:-"PLAINTEXT://localhost:9092"}
export KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=${KAFKA_LISTENER_SECURITY_PROTOCOL_MAP:-"CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"}
export KAFKA_CONTROLLER_LISTENER_NAMES=${KAFKA_CONTROLLER_LISTENER_NAMES:-"CONTROLLER"}
export KAFKA_CONTROLLER_QUORUM_VOTERS=${KAFKA_CONTROLLER_QUORUM_VOTERS:-"1@localhost:9093"}
export KAFKA_PROCESS_ROLES=${KAFKA_PROCESS_ROLES:-"broker,controller"}
export KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS:-"/var/lib/kafka/data"}
export KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=${KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR:-1}
export KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=${KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR:-1}
export KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=${KAFKA_TRANSACTION_STATE_LOG_MIN_ISR:-1}
export KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=${KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS:-0}
export KAFKA_AUTO_CREATE_TOPICS_ENABLE=${KAFKA_AUTO_CREATE_TOPICS_ENABLE:-false}

# Generate cluster ID if not provided
if [ -z "$CLUSTER_ID" ]; then
    export CLUSTER_ID=$(kafka-storage random-uuid)
    echo "Generated Cluster ID: $CLUSTER_ID"
fi

# Create config directory
mkdir -p /etc/kafka/kraft

# Create server.properties for KRaft mode
cat > /etc/kafka/kraft/server.properties <<EOF
# Server Basics
node.id=$KAFKA_NODE_ID
process.roles=$KAFKA_PROCESS_ROLES

# Listeners
listeners=$KAFKA_LISTENERS
advertised.listeners=$KAFKA_ADVERTISED_LISTENERS
listener.security.protocol.map=$KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
controller.listener.names=$KAFKA_CONTROLLER_LISTENER_NAMES
inter.broker.listener.name=PLAINTEXT

# Controller
controller.quorum.voters=$KAFKA_CONTROLLER_QUORUM_VOTERS

# Log Basics
log.dirs=$KAFKA_LOG_DIRS
num.partitions=10
default.replication.factor=$KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR

# Log Retention
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# Internal Topic Settings
offsets.topic.replication.factor=$KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
transaction.state.log.replication.factor=$KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
transaction.state.log.min.isr=$KAFKA_TRANSACTION_STATE_LOG_MIN_ISR

# Group Coordinator
group.initial.rebalance.delay.ms=$KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS

# Other Settings
auto.create.topics.enable=$KAFKA_AUTO_CREATE_TOPICS_ENABLE
compression.type=producer
delete.topic.enable=true
EOF

# Format storage if not already formatted
if [ ! -f "$KAFKA_LOG_DIRS/meta.properties" ]; then
    echo "Formatting Kafka storage..."
    kafka-storage format -t $CLUSTER_ID -c /etc/kafka/kraft/server.properties
fi

echo "Starting Kafka server..."
exec kafka-server-start /etc/kafka/kraft/server.properties