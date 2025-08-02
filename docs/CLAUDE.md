# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Development Commands

### Building Services

**Discovery Service:**
```bash
cd discovery
go mod tidy
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-w -s" -o discovery .
```

**Processor Service:**
```bash
cd processor
go mod tidy
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="-w -s" -o processor .
```

### Docker Build Commands
```bash
# Build discovery service
docker build -t aurora-discovery:latest discovery/

# Build processor service
docker build -t aurora-processor:latest processor/

# Build Kafka
docker build -t aurora-kafka:latest kafka/

# Build OpenObserve
docker build -t aurora-openobserve:latest openobserve/
```

### Running Services Locally

**Start Kafka:**
```bash
cd kafka
./start-kafka.sh
```

**Start OpenObserve:**
```bash
cd openobserve
./start.sh
```

### Kubernetes Deployment
```bash
# Apply all K8s configurations in order
kubectl apply -f k8s/setup.yaml
kubectl apply -f k8s/configmaps/
kubectl apply -f k8s/services/
kubectl apply -f k8s/deployments/
kubectl apply -f k8s/daemonsets/
kubectl apply -f k8s/ingress/
```

## Architecture Overview

This is a distributed log collection and analysis system for AWS Aurora databases consisting of:

1. **Discovery Service** (`discovery/main.go`): 
   - Discovers Aurora instances and their log files
   - Monitors log file changes via DynamoDB tracking
   - Publishes log file metadata to Kafka topics
   - Implements sharding and rate limiting for scalability

2. **Processor Service** (`processor/main.go`):
   - Consumes log file metadata from Kafka
   - Downloads log files from S3
   - Parses log content and extracts structured data
   - Sends parsed logs to OpenObserve for storage and analysis

3. **Kafka**: Message broker using KRaft mode (no ZooKeeper)
   - Topic: `aurora-logs` for log file discovery events
   
4. **OpenObserve**: Log analytics platform
   - Stores logs in S3 bucket: `company-aurora-logs-poc`
   - Provides search and visualization capabilities

5. **Fluent Bit** (configured but not primary component):
   - Kubernetes daemonset for container log collection

## Key Technologies and Patterns

- **Language**: Go 1.24 for both discovery and processor services
- **AWS Integration**: Uses AWS SDK for DynamoDB, RDS, and S3 operations
- **Message Queue**: Kafka 4.0 in KRaft mode
- **Container Runtime**: Alpine Linux base images for minimal footprint
- **Orchestration**: Kubernetes with proper service accounts and RBAC
- **Caching**: Valkey (Redis fork) for distributed caching
- **Log Analytics**: OpenObserve v0.15 with S3 backend

## Configuration

Key configuration is managed through Kubernetes ConfigMaps:
- DynamoDB table: `aurora-log-tracking`
- S3 bucket: `company-aurora-logs-poc`
- Kafka brokers: `kafka-service.aurora-logs.svc.cluster.local:9092`
- OpenObserve: `http://openobserve-service.aurora-logs.svc.cluster.local`

Services use environment variables for configuration, with defaults in:
- `k8s/configmaps/app-config.yaml`
- Individual service start scripts