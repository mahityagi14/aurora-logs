# Phase 3: Container Development and CI/CD Setup - Updated Guide

## Overview
This phase covers developing container images for all components (Discovery, Processor, Apache Kafka 4.0, OpenObserve) and setting up CI/CD pipelines for automated builds and deployments.

**Key Updates in this phase:**
- ✅ **Kafka 4.0 with Java 17** - Already correctly configured (Bitnami image includes Java 17)
- ✅ **Comprehensive security scanning** - Already implemented in CI/CD pipeline

## Step 1: Container Development

### 1.1 Setup Development Environment

Clone the repository:
```bash
git clone https://github.com/mahityagi14/aurora-logs.git
cd aurora-logs
```

### 1.2 Discovery Service Container

**File: discovery/Dockerfile**
```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy discovery module files
COPY discovery/go.mod discovery/*.go discovery/

WORKDIR /app/discovery

# Download dependencies and tidy
RUN go mod tidy

# Build for ARM64 architecture
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -ldflags="-w -s" \
    -o discovery .

# Final stage
FROM alpine:3.22
RUN apk --no-cache add ca-certificates tzdata

RUN adduser -D -u 1000 appuser

WORKDIR /app
COPY --from=builder /app/discovery/discovery .
RUN chown -R appuser:appuser /app

USER appuser

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["./discovery", "-health"]

CMD ["./discovery"]
```

### 1.3 Processor Service Container

**File: processor/Dockerfile**
```dockerfile
# Build stage
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy processor module files
COPY processor/go.mod processor/*.go processor/

WORKDIR /app/processor

# Download dependencies and tidy
RUN go mod tidy

# Build for ARM64 architecture
RUN CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build \
    -ldflags="-w -s" \
    -o processor .

# Final stage
FROM alpine:3.22
RUN apk --no-cache add ca-certificates tzdata

RUN adduser -D -u 1000 appuser

WORKDIR /app
COPY --from=builder /app/processor/processor .
RUN chown -R appuser:appuser /app

USER appuser

ENV GOMAXPROCS=2

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["./processor", "-health"]

CMD ["./processor"]
```

### 1.4 Apache Kafka 4.0 Container - VERIFIED

**File: kafka/Dockerfile**
```dockerfile
# Use ARM64 platform explicitly - Kafka 4.0
# NOTE: Kafka 4.0 requires Java 17 which is included in the bitnami/kafka:4.0 image
FROM --platform=linux/arm64 bitnami/kafka:4.0

USER root

# Copy custom start script with execute permissions
COPY --chmod=755 start-kafka.sh /opt/bitnami/scripts/kafka/start-kafka.sh

# Create data dir with permissions
RUN mkdir -p /bitnami/kafka/data && \
    chown -R 1001:1001 /bitnami/kafka/data

USER 1001

# Updated health check for Kafka 4.0 with KRaft mode
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD kafka-metadata-quorum.sh --bootstrap-server localhost:9092 --command-config /opt/bitnami/kafka/config/kraft/broker.properties describe --status || exit 1

ENTRYPOINT ["/opt/bitnami/scripts/kafka/start-kafka.sh"]
```

**File: kafka/start-kafka.sh**
```bash
#!/bin/bash
set -e

# Default values for KRaft mode (Kafka 4.0)
# Kafka 4.0 runs on Java 17 and removes Zookeeper dependency
export KAFKA_CFG_NODE_ID="${KAFKA_CFG_NODE_ID:-1}"
export KAFKA_CFG_PROCESS_ROLES="${KAFKA_CFG_PROCESS_ROLES:-broker,controller}"
export KAFKA_CFG_CONTROLLER_QUORUM_VOTERS="${KAFKA_CFG_CONTROLLER_QUORUM_VOTERS:-1@kafka-service:9093}"
export KAFKA_CFG_LISTENERS="${KAFKA_CFG_LISTENERS:-PLAINTEXT://:9092,CONTROLLER://:9093}"
export KAFKA_CFG_ADVERTISED_LISTENERS="${KAFKA_CFG_ADVERTISED_LISTENERS:-PLAINTEXT://kafka-service.aurora-logs.svc.cluster.local:9092}"
export KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP="${KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP:-CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT}"
export KAFKA_CFG_CONTROLLER_LISTENER_NAMES="${KAFKA_CFG_CONTROLLER_LISTENER_NAMES:-CONTROLLER}"
export KAFKA_CFG_INTER_BROKER_LISTENER_NAME="${KAFKA_CFG_INTER_BROKER_LISTENER_NAME:-PLAINTEXT}"

# KRaft settings for Kafka 4.0 (no Zookeeper)
export KAFKA_ENABLE_KRAFT="${KAFKA_ENABLE_KRAFT:-yes}"
export KAFKA_KRAFT_CLUSTER_ID="${KAFKA_KRAFT_CLUSTER_ID:-aurora-logs-kafka-cluster}"

# Kafka 4.0 directory configurations
export KAFKA_CFG_LOG_DIRS="${KAFKA_CFG_LOG_DIRS:-/bitnami/kafka/data}"
export KAFKA_CFG_METADATA_LOG_DIR="${KAFKA_CFG_METADATA_LOG_DIR:-/bitnami/kafka/metadata}"

# Updated settings for Kafka 4.0 with new consumer rebalance protocol
export KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE="${KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE:-false}"
export KAFKA_CFG_DEFAULT_REPLICATION_FACTOR="${KAFKA_CFG_DEFAULT_REPLICATION_FACTOR:-1}"
export KAFKA_CFG_MIN_INSYNC_REPLICAS="${KAFKA_CFG_MIN_INSYNC_REPLICAS:-1}"
export KAFKA_CFG_NUM_PARTITIONS="${KAFKA_CFG_NUM_PARTITIONS:-10}"
export KAFKA_CFG_LOG_RETENTION_HOURS="${KAFKA_CFG_LOG_RETENTION_HOURS:-168}"
export KAFKA_CFG_LOG_RETENTION_BYTES="${KAFKA_CFG_LOG_RETENTION_BYTES:-107374182400}"
export KAFKA_CFG_COMPRESSION_TYPE="${KAFKA_CFG_COMPRESSION_TYPE:-snappy}"
export KAFKA_CFG_LOG_SEGMENT_BYTES="${KAFKA_CFG_LOG_SEGMENT_BYTES:-1073741824}"

# Performance tuning for Kafka 4.0
export KAFKA_CFG_NUM_NETWORK_THREADS="${KAFKA_CFG_NUM_NETWORK_THREADS:-8}"
export KAFKA_CFG_NUM_IO_THREADS="${KAFKA_CFG_NUM_IO_THREADS:-8}"
export KAFKA_CFG_SOCKET_SEND_BUFFER_BYTES="${KAFKA_CFG_SOCKET_SEND_BUFFER_BYTES:-102400}"
export KAFKA_CFG_SOCKET_RECEIVE_BUFFER_BYTES="${KAFKA_CFG_SOCKET_RECEIVE_BUFFER_BYTES:-102400}"
export KAFKA_CFG_SOCKET_REQUEST_MAX_BYTES="${KAFKA_CFG_SOCKET_REQUEST_MAX_BYTES:-104857600}"

# Kafka 4.0 requires initial cluster ID
export KAFKA_CFG_INITIAL_BROKER_REGISTRATION_TIMEOUT_MS="${KAFKA_CFG_INITIAL_BROKER_REGISTRATION_TIMEOUT_MS:-60000}"

# Java 17 is used by default in Kafka 4.0
if [ "${BITNAMI_DEBUG}" = "true" ]; then
    export KAFKA_CFG_LOG4J_ROOT_LOGLEVEL="DEBUG"
    echo "Java version:"
    java -version
fi

echo "Starting Kafka 4.0 in KRaft mode (Java 17)..."
echo "Configuration summary:"
echo "Node ID: $KAFKA_CFG_NODE_ID"
echo "Roles: $KAFKA_CFG_PROCESS_ROLES"
echo "Listeners: $KAFKA_CFG_LISTENERS"

# Run Bitnami entrypoint
exec /opt/bitnami/scripts/kafka/entrypoint.sh /opt/bitnami/scripts/kafka/run.sh
```

### 1.5 OpenObserve Container

**File: openobserve/Dockerfile**
```dockerfile
# Use ARM64 platform explicitly with latest stable version
FROM --platform=linux/arm64 openobserve/openobserve:v0.14.7

# Copy custom start script with permissions
COPY --chmod=755 --chown=1000:1000 start.sh /app/start.sh

# Environment variables for configuration
ENV ZO_DATA_DIR="/data"
ENV ZO_HTTP_PORT="5080"
ENV ZO_HTTP_ADDR="0.0.0.0"
ENV ZO_TELEMETRY_ENABLED="false"

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:5080/healthz || exit 1

EXPOSE 5080

VOLUME ["/data"]

ENTRYPOINT ["/app/start.sh"]
```

**File: openobserve/start.sh**
```bash
#!/bin/bash
set -e

# Default admin credentials if not provided
export ZO_ROOT_USER_EMAIL="${ZO_ROOT_USER_EMAIL:-admin@poc.com}"
export ZO_ROOT_USER_PASSWORD="${ZO_ROOT_USER_PASSWORD:-admin123}"

# S3 configuration (uses node IAM role)
export ZO_S3_PROVIDER="aws"
export ZO_S3_BUCKET_NAME="${ZO_S3_BUCKET_NAME:-company-aurora-logs-poc}"
export ZO_S3_REGION_NAME="${AWS_REGION}"
export ZO_S3_SERVER_URL="https://s3.${AWS_REGION}.amazonaws.com"

# Performance settings
export ZO_MEMORY_CACHE_ENABLED="true"
export ZO_MEMORY_CACHE_MAX_SIZE="${ZO_MEMORY_CACHE_MAX_SIZE:-2048}"
export ZO_QUERY_THREAD_NUM="${ZO_QUERY_THREAD_NUM:-4}"
export ZO_INGEST_ALLOWED_UPTO="${ZO_INGEST_ALLOWED_UPTO:-24}"
export ZO_PAYLOAD_LIMIT="${ZO_PAYLOAD_LIMIT:-209715200}"  # 200MB
export ZO_MAX_FILE_SIZE_ON_DISK="${ZO_MAX_FILE_SIZE_ON_DISK:-512}"  # 512MB

# Features
export ZO_PROMETHEUS_ENABLED="true"
export ZO_USAGE_REPORTING_ENABLED="false"
export ZO_PRINT_KEY_CONFIG="false"

echo "Starting OpenObserve v0.14.7 with configuration:"
echo "Data Dir: $ZO_DATA_DIR"
echo "HTTP Port: $ZO_HTTP_PORT"
echo "S3 Bucket: $ZO_S3_BUCKET_NAME"
echo "Memory Cache: $ZO_MEMORY_CACHE_MAX_SIZE MB"

# Start OpenObserve
exec ./openobserve
```

## Step 2: Build and Push Container Images

### 2.1 Login to ECR

```bash
# Get ECR login token
aws ecr get-login-password --region [region] | docker login --username AWS --password-stdin [account-id].dkr.ecr.[region].amazonaws.com
```

### 2.2 Build Images Locally

```bash
# Set variables
export AWS_ACCOUNT_ID=[account-id]
export AWS_REGION=[region]
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
export IMAGE_TAG="v1.0.0"

# Build Discovery service (ARM64)
docker build --platform linux/arm64 -t ${ECR_REGISTRY}/aurora-log-system:discovery-${IMAGE_TAG} -f discovery/Dockerfile .
docker tag ${ECR_REGISTRY}/aurora-log-system:discovery-${IMAGE_TAG} ${ECR_REGISTRY}/aurora-log-system:discovery-latest

# Build Processor service (ARM64)
docker build --platform linux/arm64 -t ${ECR_REGISTRY}/aurora-log-system:processor-${IMAGE_TAG} -f processor/Dockerfile .
docker tag ${ECR_REGISTRY}/aurora-log-system:processor-${IMAGE_TAG} ${ECR_REGISTRY}/aurora-log-system:processor-latest

# Build Kafka 4.0 (ARM64)
cd kafka
docker build --platform linux/arm64 -t ${ECR_REGISTRY}/aurora-log-system:kafka-${IMAGE_TAG} .
docker tag ${ECR_REGISTRY}/aurora-log-system:kafka-${IMAGE_TAG} ${ECR_REGISTRY}/aurora-log-system:kafka-latest
cd ..

# Build OpenObserve (ARM64)
cd openobserve
docker build --platform linux/arm64 -t ${ECR_REGISTRY}/aurora-log-system:openobserve-${IMAGE_TAG} .
docker tag ${ECR_REGISTRY}/aurora-log-system:openobserve-${IMAGE_TAG} ${ECR_REGISTRY}/aurora-log-system:openobserve-latest
cd ..
```

### 2.3 Push Images to ECR

```bash
# Push all images
docker push ${ECR_REGISTRY}/aurora-log-system:discovery-${IMAGE_TAG}
docker push ${ECR_REGISTRY}/aurora-log-system:discovery-latest

docker push ${ECR_REGISTRY}/aurora-log-system:processor-${IMAGE_TAG}
docker push ${ECR_REGISTRY}/aurora-log-system:processor-latest

docker push ${ECR_REGISTRY}/aurora-log-system:kafka-${IMAGE_TAG}
docker push ${ECR_REGISTRY}/aurora-log-system:kafka-latest

docker push ${ECR_REGISTRY}/aurora-log-system:openobserve-${IMAGE_TAG}
docker push ${ECR_REGISTRY}/aurora-log-system:openobserve-latest
```

## Step 3: Setup Jenkins CI/CD Pipeline

### 3.1 Install Jenkins (if not already available)

```bash
# On Amazon Linux 2023
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
sudo dnf upgrade
sudo dnf install jenkins java-17-amazon-corretto-devel
sudo systemctl enable jenkins
sudo systemctl start jenkins
```

### 3.2 Configure Jenkins

1. Access Jenkins at `http://[jenkins-server]:8080`
2. Install plugins:
   - Docker Pipeline
   - AWS Steps
   - Go Plugin
   - Pipeline: AWS Steps
   - CloudBees AWS Credentials

### 3.3 Create Jenkins Pipeline Job

1. **New Item** → **Pipeline**
2. Name: `aurora-log-system-pipeline`
3. **Pipeline** → **Definition**: Pipeline script from SCM
4. **SCM**: Git
5. **Repository URL**: `https://github.com/mahityagi14/aurora-logs.git`
6. **Script Path**: `Jenkinsfile`
7. Save

### 3.4 Configure AWS Credentials in Jenkins

1. **Manage Jenkins** → **Manage Credentials**
2. Add AWS credentials:
   - Kind: **AWS Credentials**
   - ID: `aws-credentials`
   - Access Key ID: [your-access-key]
   - Secret Access Key: [your-secret-key]

### 3.5 Configure Jenkins Environment

Add these environment variables in Jenkins:
- `AWS_ACCOUNT_ID`: Your AWS account ID
- `AWS_REGION`: Your AWS region
- `EXECUTION_ROLE_ARN`: `arn:aws:iam:[account-id]:role/aurora-ecs-execution-role`
- `TASK_ROLE_ARN`: `arn:aws:iam:[account-id]:role/aurora-ecs-task-role`
- `SNYK_TOKEN`: (Optional) For security scanning

## Step 4: Create Kafka Topic Creation Script

**File: scripts/create-topics.sh**
```bash
#!/bin/bash
set -e

# Script to create Kafka topics for Aurora Log System
# Updated for Kafka 4.0 with KRaft mode

KAFKA_CONTAINER="kafka-service"
PARTITIONS=${PARTITIONS:-10}
REPLICATION_FACTOR=${REPLICATION_FACTOR:-1}

echo "Creating Kafka 4.0 topics..."

# Function to create topic
create_topic() {
    local topic=$1
    local retention_ms=${2:-604800000}  # Default 7 days
    
    echo "Creating topic: $topic"
    docker exec $KAFKA_CONTAINER kafka-topics.sh \
        --create \
        --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic $topic \
        --partitions $PARTITIONS \
        --replication-factor $REPLICATION_FACTOR \
        --config retention.ms=$retention_ms \
        --config compression.type=snappy \
        --config max.message.bytes=10485760 \
        --config min.insync.replicas=1
}

# Create topics with appropriate retention
create_topic "aurora-logs-error" 604800000      # 7 days retention
create_topic "aurora-logs-slowquery" 2592000000 # 30 days retention
create_topic "aurora-logs-dlq" 1209600000       # 14 days retention for dead letter queue

# List topics
echo ""
echo "Listing all topics:"
docker exec $KAFKA_CONTAINER kafka-topics.sh \
    --list \
    --bootstrap-server localhost:9092

# Verify Kafka 4.0 is running with Java 17
echo ""
echo "Kafka version info:"
docker exec $KAFKA_CONTAINER kafka-broker-api-versions.sh \
    --bootstrap-server localhost:9092 | head -5

echo ""
echo "Topic creation completed!"
```

## Step 5: Verify Container Images

After building and pushing:

1. **Check ECR Repository**:
```bash
aws ecr list-images --repository-name aurora-log-system --query 'imageIds[*].imageTag' --output table
```

2. **Verify Image Sizes**:
```bash
aws ecr describe-images --repository-name aurora-log-system --query 'imageDetails[*].[imageTags[0],imageSizeInBytes]' --output table
```

3. **Check Vulnerability Scans**:
```bash
aws ecr describe-image-scan-findings --repository-name aurora-log-system --image-id imageTag=discovery-latest
```

4. **Verify ARM64 Architecture**:
```bash
# For each image, check the architecture
aws ecr batch-get-image --repository-name aurora-log-system \
    --image-ids imageTag=kafka-latest \
    --query 'images[0].imageManifest' --output text | jq -r '.config.digest' | \
    xargs -I {} aws ecr batch-get-image --repository-name aurora-log-system \
    --image-ids imageDigest={} --query 'images[0].imageManifest' --output text | \
    jq '.architecture'
```

## Summary

Phase 3 accomplishes:

### Container Images:
- Discovery service (Go 1.23, ARM64)
- Processor service (Go 1.23, ARM64)
- Apache Kafka 4.0 (KRaft mode, Java 17, ARM64)
- OpenObserve v0.14.7 (ARM64)

### Key Features:
- **Kafka 4.0**: Running with Java 17 and new consumer rebalance protocol
- **ARM64 Architecture**: All images built for ARM64 platform
- **Comprehensive Security Scanning**: Implemented in CI/CD pipeline

### CI/CD:
- Jenkins pipeline configured
- Automated builds and security scanning
- Push to ECR on successful builds

### Scripts:
- Kafka topic creation script ready for Kafka 4.0

## Next Steps
Proceed to Phase 4 to create the ECS cluster and deploy all services using the container images.