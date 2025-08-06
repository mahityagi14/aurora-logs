# Aurora Log System Architecture

## Project Overview

**Problem Statement**: CloudWatch Logs costs for Aurora MySQL RDS are high due to:
- Log ingestion costs for 316 Aurora MySQL db.r6g.2xlarge instances
- CloudWatch storage costs  
- Query costs for log analysis

**Solution**: Build a cost-effective log collection system that:
- Uses RDS API to fetch logs directly (avoiding CloudWatch ingestion)
- Stores logs in S3 using OpenObserve's efficient format
- Provides searchable log analytics at a fraction of the cost

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   AWS Cloud Infrastructure                               │
│                                                                                          │
│  ┌─────────────────────┐              ┌─────────────────────────────────────┐          │
│  │  316 Aurora MySQL   │              │         S3 Buckets                  │          │
│  │  db.r6g.2xlarge     │              │  ┌────────────────────────────┐     │          │
│  │    Instances        │              │  │ company-aurora-logs-poc    │     │          │
│  │                     │              │  │ (Aurora error/slowquery)   │     │          │
│  │ ┌─────────────────┐ │              │  └────────────────────────────┘     │          │
│  │ │ RDS API Access  │ │              │  ┌────────────────────────────┐     │          │
│  │ │ - DescribeDB*   │ │              │  │ aurora-k8s-logs-072006186126│     │          │
│  │ │ - Log Files     │ │              │  │ (Kubernetes pod logs)      │     │          │
│  │ └─────────────────┘ │              │  └────────────────────────────┘     │          │
│  └─────────────────────┘              └─────────────────────────────────────┘          │
│                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────┐          │
│  │                           DynamoDB Tables                                │          │
│  │  • aurora-instance-metadata    - RDS instance information               │          │
│  │  • aurora-log-file-tracking    - Log file processing state              │          │
│  │  • aurora-log-processing-jobs  - Processing job coordination            │          │
│  └─────────────────────────────────────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            │ RDS API / S3 API
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│            EKS Cluster: aurora-logs-poc-cluster (v1.33) - Single Node                   │
│            Node Group: aurora-node-47 (t4g.large SPOT ARM64 - AL2023)                   │
│                                                                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              Log Discovery Pipeline                               │   │
│  │                                                                                   │   │
│  │  ┌─────────────────┐         ┌──────────────────┐        ┌──────────────────┐   │   │
│  │  │ Discovery Service│         │   Kafka (Single  │        │ Processor Service│   │   │
│  │  │                 │ Publish │   Node - KRaft)  │Consume │                  │   │   │
│  │  │ • Poll RDS API  │────────►│                  │◄───────│ • Download logs  │   │   │
│  │  │ • Track in      │         │ Topics:          │        │   from RDS API   │   │   │
│  │  │   DynamoDB      │         │ • aurora-error-  │        │ • Parse logs     │   │   │
│  │  │ • Use Valkey    │         │   logs           │        │   internally     │   │   │
│  │  │   cache         │         │ • aurora-        │        │ • Send directly  │   │   │
│  │  └────────┬────────┘         │   slowquery-logs │        │   to OpenObserve │   │   │
│  │           │                  │                  │        └─────────┬────────┘   │   │
│  │           │                  └──────────────────┘                   │            │   │
│  │           │ Cache RDS                                               │ Forward    │   │
│  │           │ API calls                                               │ logs       │   │
│  │           ▼                                                         │            │   │
│  │  ┌─────────────────┐                                               │            │   │
│  │  │     Valkey      │                                               │            │   │
│  │  │  (Redis Fork)   │                                               │            │   │
│  │  │                 │                                               │            │   │
│  │  │ Reduce RDS API  │                                               │            │   │
│  │  │ calls by caching│                                               │            │   │
│  │  └─────────────────┘                                               │            │   │
│  │                                                                    │            │   │
│  └────────────────────────────────────────────────────────────────────┼────────────┘   │
│                                                          │                            │
│  ┌───────────────────────────────────────────────────────▼───────────────────────┐   │
│  │                     Observability & Analytics Layer                           │   │
│  │                                                                               │   │
│  │  ┌─────────────────────────┐                                                 │   │
│  │  │      OpenObserve        │                                                 │   │
│  │  │                         │                                                 │   │
│  │  │  3 Streams:             │                                                 │   │
│  │  │  • aurora_logs          │                                                 │   │
│  │  │  • aurora_error_logs    │                                                 │   │
│  │  │  • aurora_slowquery_logs│                                                 │   │
│  │  │                         │                                                 │   │
│  │  │  Storage Backend:       │                                                 │   │
│  │  │  • S3 (efficient format)│                                                 │   │
│  │  └─────────────────────────┘                                                 │   │
│  └───────────────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Log Discovery Flow
```
Aurora RDS (316 instances) → RDS API → Discovery Service → Kafka → Processor
```

1. **Discovery Service** polls RDS API:
   - Discovers all 316 Aurora MySQL db.r6g.2xlarge instances
   - For each instance, lists available log files via RDS API
   - Tracks when each log file was created in DynamoDB
   - Publishes log file metadata to Kafka for processing
   - Uses Valkey to cache RDS API responses (reduce API calls)
   - Polling interval: 5 minutes

2. **Kafka Message Queue** (Single node):
   - Topics (auto-created):
     - `aurora-error-logs`: Error log file metadata (10 partitions)
     - `aurora-slowquery-logs`: Slow query log metadata (10 partitions)
   - Consumer group: `aurora-processor-group`

### 2. Log Processing Flow
```
Kafka → Processor → RDS API (Download) → Parse → OpenObserve → S3
```

1. **Processor Service**:
   - Consumes log file metadata from Kafka
   - Downloads actual log content via RDS API (DownloadDBLogFilePortion)
   - Parses logs internally (no Fluent Bit integration)
   - Sends parsed logs directly to OpenObserve HTTP API
   - Updates processing state in DynamoDB

2. **OpenObserve** (Storage & Analytics):
   - Receives parsed logs via HTTP
   - Stores in 3 separate streams (auto-initialized during deployment):
     - `aurora_logs` → General log stream
     - `aurora_error_logs` → Error logs only
     - `aurora_slowquery_logs` → Slow query logs only
   - All stored in company-aurora-logs-poc S3 bucket
   - Provides searchable UI and API
   - Note: Streams must be initialized before first data push

### 3. Metrics Collection Flow
```
All Services → Prometheus Metrics Endpoint → Monitoring
```

- Services expose Prometheus metrics on port 9090
- Metrics include processing rates, errors, and system health
- Can be scraped by external monitoring systems

## Component Details

### Core Services

#### Discovery Service
- **Image**: `072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:discovery-latest`
- **Purpose**: Discover Aurora instances and their log files
- **Key Operations**:
  - Poll RDS API to list all Aurora MySQL instances
  - For each instance, check for new log files
  - Track processed files in DynamoDB to avoid duplicates
  - Publish new log files to Kafka for processing
  - Cache RDS API responses in Valkey

#### Processor Service  
- **Image**: `072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:processor-latest`
- **Purpose**: Download, parse, and send logs to OpenObserve
- **Key Operations**:
  - Consume log file metadata from Kafka
  - Download log content via RDS API (DownloadDBLogFilePortion)
  - Parse Aurora MySQL error and slowquery logs
  - Send parsed logs directly to OpenObserve HTTP API
  - Update processing checkpoints in DynamoDB
  - Handle retries with circuit breaker pattern

### Infrastructure Components

#### Kafka (Single Node)
- **Image**: `bitnami/kafka:4.0.0`
- **Mode**: KRaft (no Zookeeper)
- **Configuration**:
  - Single node only (as per requirement)
  - Auto-create topics enabled (no manual topic creation)
  - Topics: aurora-error-logs, aurora-slowquery-logs (10 partitions each)
  - Retention: 24 hours
  - Compression: LZ4

#### OpenObserve
- **Image**: `openobserve/openobserve:v0.15.0-rc4-arm64`
- **Streams**:
  - `aurora_logs`: All Aurora logs
  - `aurora_error_logs`: Aurora error logs only
  - `aurora_slowquery_logs`: Aurora slow query logs only
- **Storage**:
  - All logs → company-aurora-logs-poc S3 bucket
  - Uses efficient columnar format for storage
- **Access**:
  - Web UI with search capabilities
  - HTTP API for log ingestion
  - ALB endpoint: openobserve-alb-355407172.us-east-1.elb.amazonaws.com

#### Valkey
- **Image**: `valkey/valkey:8.1.3`
- **Purpose**: Reduce RDS API calls through caching
- **Cache Items**:
  - RDS instance lists
  - Log file metadata
  - API responses

## AWS Infrastructure (Existing Resources)

### EKS Cluster
- **Name**: aurora-logs-poc-cluster (v1.33)
- **Node Group**: aurora-node-47
- **Instance Type**: t4g.large (ARM64/Graviton2) - SPOT
- **Nodes**: 1 (min:1, max:1)
- **AMI**: AL2023_ARM_64_STANDARD
- **Disk**: 50GB

### DynamoDB Tables
- `aurora-instance-metadata`: Stores RDS instance information
- `aurora-log-file-tracking`: Tracks processed log files
- `aurora-log-processing-jobs`: Coordinates processing jobs
- `aurora-log-tracking`: Processing state and checkpoints

### S3 Buckets
- `company-aurora-logs-poc`: Aurora error and slowquery logs (OpenObserve format)
- `aurora-k8s-logs-072006186126`: Kubernetes pod logs

### IAM Roles & Authentication
- **EKS Pod Identity** (not IRSA/OIDC):
  - `AuroraLogDiscoveryRole`: Attached to discovery-sa service account
  - `AuroraLogProcessorRole`: Attached to processor-sa service account
  - `AuroraLogOpenObserveRole`: Attached to openobserve-sa service account
- **IAM Policy**: `aurora-log-system-policy` attached to all roles
  - RDS API access (DescribeDB*, DownloadDBLogFilePortion)
  - DynamoDB access for state tracking
  - S3 access for OpenObserve storage
- **EKS Admin**: `aurora-logs-eks-admin-role` for cluster management

## Key Design Decisions

### Cost Optimization
1. **Bypass CloudWatch**: Direct RDS API access eliminates CloudWatch ingestion costs
2. **Single Kafka Node**: Sufficient for log metadata queue with auto-create topics
3. **Valkey Caching**: Reduces RDS API calls (API rate limits)
4. **S3 Storage**: OpenObserve uses efficient columnar format in S3
5. **SPOT Instance**: t4g.large SPOT reduces EC2 costs by ~70%
6. **No Fluent Bit**: Direct parsing in processor reduces complexity
7. **EKS Pod Identity**: Simpler than IRSA/OIDC for IAM permissions

### Log Filtering
- **Only Error and Slow Query Logs**: General logs are filtered out
- **At Processor Layer**: Parser identifies log types during processing
- **Separate Streams**: Different OpenObserve streams for different log types

### Scaling Strategy
- **Discovery Service**: HPA scales 1-2 replicas based on CPU (80%)
- **Processor Service**: HPA scales 1-10 replicas based on CPU (60%) and memory (70%)
- **Kafka**: Single node (no replication needed for POC)
- **OpenObserve**: Single instance sufficient for POC workload

## Security Considerations

### Network
- All services run within EKS cluster
- No external load balancers required
- Service-to-service communication via ClusterIP

### Authentication
- IAM roles for AWS service access
- No hardcoded credentials
- Service accounts with proper RBAC

### Data Protection
- Logs encrypted at rest in S3
- TLS for service communication
- No PII filtering (handled by Aurora log settings)

## Timestamp Preservation

**Critical Requirement**: Aurora log timestamps must appear exactly as generated in OpenObserve.

### How Timestamps Are Preserved

1. **Aurora Generation**: Aurora writes logs with original timestamps
   ```
   2025-08-03 15:30:45 123456 [ERROR] Connection timeout
   ```

2. **Processor Parsing**: 
   - Downloads log with timestamp intact via RDS API
   - Parser extracts timestamp: `2025-08-03 15:30:45`
   - Converts to ISO format for OpenObserve
   - Sets `_timestamp` field in milliseconds

3. **OpenObserve Storage**: 
   - Uses `_timestamp` field (not ingestion time)
   - Log appears at exact Aurora generation time
   - Searchable by original timestamp

### Configuration
```go
// Processor preserves timestamp
log.Timestamp = parseAuroraTimestamp(line)
openObservePayload["_timestamp"] = log.Timestamp.UnixMilli()
```

## Metrics & Monitoring

### Prometheus Metrics
- All services expose metrics on port 9090
- Metrics endpoint: `/metrics`
- Format: Prometheus text format

### Available Metrics
1. **Service Health**
   - `up` - Service availability
   - `process_cpu_seconds_total` - CPU usage
   - `process_resident_memory_bytes` - Memory usage

2. **Processing Metrics**
   - `logs_processed_total` - Total logs processed
   - `log_processing_duration_seconds` - Processing time
   - `log_processing_errors_total` - Error count

3. **Queue Metrics**
   - `kafka_consumer_lag` - Consumer lag per topic
   - `kafka_messages_consumed_total` - Messages processed

### OpenObserve Analytics
- Log volume trends by type
- Error rate analysis
- Slow query patterns
- Search and filter capabilities

## Complete AWS Infrastructure

### Container Registry
- **ECR Repository**: `072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system`
  - Images: discovery-latest, processor-latest

### VPC Resources
- **VPC**: vpc-0709b8bef0bf79401
- **Subnets**: 
  - Public: subnet-09a05d3f60260977d, subnet-02be44306a0c4a66f
  - Private: subnet-065f0d4951fc12ef9, subnet-0726157ced0ebe2cf

### Security Groups
- `sg-0c67e6b50814f89df`: EKS cluster security group
- `sg-052a7b718e534fed9`: EKS node security group
- `sg-0df4c3eb67e0739fb`: ALB security group
- `sg-0b15c8fdb8b0770a2`: Valkey security group
- `sg-0781a0b7315baf1ab`: Aurora MySQL security group

### Cost Comparison

**CloudWatch Logs (Current)**:
- Ingestion: $0.50/GB × ~1TB/day × 30 days = $15,000/month
- Storage: $0.03/GB × ~30TB = $900/month  
- Queries: $0.005/GB scanned
- **Total**: ~$16,000+/month

**Aurora Log System (New)**:
- EKS: t4g.large SPOT = ~$30/month (70% discount)
- S3 Storage: $0.023/GB × ~30TB = $690/month
- DynamoDB: ~$50/month
- API calls: Minimal
- ALB: ~$20/month
- **Total**: ~$800/month

**Savings**: ~95% reduction in logging costs

## Current Deployment Status

### Active Components
- **Namespace**: aurora-logs
- **Services Running**:
  - Discovery Service (1-2 replicas with HPA)
  - Processor Service (1-10 replicas with HPA)
  - Kafka (single node, KRaft mode with auto-create topics)
  - OpenObserve (with ALB access and stream initialization)
  - Valkey (Redis fork for caching)

### Deployment Features
- **One-Click Deployment**: `./one-click-deploy.sh` handles complete setup
- **AZ-Aware Deployment**: Automatically handles EBS volume zone affinity
- **Health Checks**: Removed from all services to prevent unnecessary restarts
- **Stream Initialization**: OpenObserve streams created automatically during deployment
- **IAM Permissions**: Automatically configured via EKS Pod Identity

### Unused Components (Not Deployed)
- Fluent Bit (parsing done in processor)
- OTEL Collector (metrics via Prometheus endpoints)
- Vector (alternative log shipper)
- Health check probes (removed to prevent restarts)

### Access Points
- **OpenObserve UI**: http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com
- **Credentials**: admin@example.com / Complexpass#123
- **Kubernetes**: kubectl access via aurora-logs-eks-admin-role