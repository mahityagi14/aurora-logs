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
│            Node Group: aurora-node-2 (t4g.2xlarge ARM64 - AL2023)                       │
│                                                                                          │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐   │
│  │                              Log Discovery Pipeline                               │   │
│  │                                                                                   │   │
│  │  ┌─────────────────┐         ┌──────────────────┐        ┌──────────────────┐   │   │
│  │  │ Discovery Service│         │   Kafka (Single  │        │ Processor Service│   │   │
│  │  │                 │ Publish │   Node - KRaft)  │Consume │                  │   │   │
│  │  │ • Poll RDS API  │────────►│                  │◄───────│ • Download logs  │   │   │
│  │  │ • Track in      │         │ Topics:          │        │   from RDS API   │   │   │
│  │  │   DynamoDB      │         │ • aurora-error-  │        │ • Forward to     │   │   │
│  │  │ • Use Valkey    │         │   logs           │        │   Fluent Bit     │   │   │
│  │  │   cache         │         │ • aurora-        │        │   via TCP        │   │   │
│  │  └────────┬────────┘         │   slowquery-logs │        └─────────┬────────┘   │   │
│  │           │                  └──────────────────┘                   │            │   │
│  │           │ Cache RDS                                               │ Forward    │   │
│  │           │ API calls                                               │ logs       │   │
│  │           ▼                                                         ▼            │   │
│  │  ┌─────────────────┐                    ┌─────────────────────────────────┐    │   │
│  │  │     Valkey      │                    │      Fluent Bit (DaemonSet)     │    │   │
│  │  │  (Redis Fork)   │                    │                                 │    │   │
│  │  │                 │                    │ • Parse error/slowquery logs    │    │   │
│  │  │ Reduce RDS API  │                    │ • Filter: Only error and       │    │   │
│  │  │ calls by caching│                    │   slowquery log types          │    │   │
│  │  └─────────────────┘                    │ • Forward to OpenObserve       │    │   │
│  │                                         └──────────────┬──────────────────┘    │   │
│  └──────────────────────────────────────────────────────┼───────────────────────┘   │
│                                                          │                            │
│  ┌───────────────────────────────────────────────────────▼───────────────────────┐   │
│  │                     Observability & Analytics Layer                           │   │
│  │                                                                               │   │
│  │  ┌─────────────────────────┐           ┌─────────────────────────┐           │   │
│  │  │      OpenObserve        │  Metrics  │   OTEL Collector        │           │   │
│  │  │                         │◄──────────│                         │           │   │
│  │  │  3 Indexes:             │           │ • Collect metrics from  │           │   │
│  │  │  • slow_search_logs     │           │   all services          │           │   │
│  │  │  • error_logs           │           │ • Export to OpenObserve │           │   │
│  │  │  • k8s_logs             │           │   dashboards            │           │   │
│  │  │                         │           └─────────────────────────┘           │   │
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

2. **Kafka Message Queue** (Single node):
   - Topics:
     - `aurora-error-logs`: Error log file metadata
     - `aurora-slowquery-logs`: Slow query log metadata

### 2. Log Processing Flow
```
Kafka → Processor → RDS API (Download) → Fluent Bit → OpenObserve → S3
```

1. **Processor Service**:
   - Consumes log file metadata from Kafka
   - Downloads actual log content via RDS API (DownloadDBLogFilePortion)
   - Forwards raw logs to Fluent Bit via TCP (localhost:24224)
   - Updates processing state in DynamoDB

2. **Fluent Bit** (Parsing layer):
   - Receives raw logs from Processor
   - Parses and filters: Only processes error and slowquery logs
   - Extracts structured fields (timestamp, query_time, etc.)
   - Forwards to OpenObserve HTTP endpoints

3. **OpenObserve** (Storage & Analytics):
   - Receives parsed logs via HTTP
   - Stores in 3 separate indexes:
     - `slow_search_logs` → company-aurora-logs-poc S3 bucket
     - `error_logs` → company-aurora-logs-poc S3 bucket  
     - `k8s_logs` → aurora-k8s-logs-072006186126 S3 bucket
   - Provides searchable UI and API

### 3. Metrics Collection Flow
```
All Services → OTEL Collector → OpenObserve Dashboards
```

- **OTEL Collector** scrapes metrics from all services
- Exports to OpenObserve for monitoring dashboards
- Tracks processing rates, errors, and system health

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
- **Purpose**: Download and forward logs to Fluent Bit
- **Key Operations**:
  - Consume log file metadata from Kafka
  - Download log content via RDS API (DownloadDBLogFilePortion)
  - Forward raw logs to Fluent Bit TCP endpoint
  - Update processing checkpoints in DynamoDB
  - Handle retries with circuit breaker pattern

### Infrastructure Components

#### Kafka (Single Node)
- **Image**: `bitnami/kafka:4.0.0`
- **Mode**: KRaft (no Zookeeper)
- **Configuration**:
  - Single node only (as per requirement)
  - Topics: aurora-error-logs, aurora-slowquery-logs
  - Retention: 24 hours
  - Compression: LZ4

#### Fluent Bit
- **Image**: `fluent/fluent-bit:4.0.5-arm64`
- **Deployment**: DaemonSet
- **Functions**:
  - Parse Aurora MySQL error and slowquery logs
  - Filter out all other log types
  - Forward to OpenObserve with proper timestamps

#### OpenObserve
- **Image**: `openobserve/openobserve:v0.15.0-rc4-arm64`
- **Indexes**:
  - `slow_search_logs`: Aurora slow query logs
  - `error_logs`: Aurora error logs
  - `k8s_logs`: Kubernetes pod logs
- **Storage**:
  - Aurora logs → company-aurora-logs-poc bucket
  - K8s logs → aurora-k8s-logs-072006186126 bucket

#### OTEL Collector
- **Image**: `otel/opentelemetry-collector-contrib:0.131.1-arm64`
- **Purpose**: Collect metrics for OpenObserve dashboards
- **Metrics Sources**:
  - Service health metrics
  - Processing rates
  - Error counts

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
- **Node Group**: aurora-node-2
- **Instance Type**: t4g.2xlarge (ARM64/Graviton2)
- **Nodes**: 1 (min:1, max:1)
- **AMI**: AL2023_ARM_64_STANDARD

### DynamoDB Tables
- `aurora-instance-metadata`: Stores RDS instance information
- `aurora-log-file-tracking`: Tracks processed log files
- `aurora-log-processing-jobs`: Coordinates processing jobs
- `aurora-log-tracking`: Processing state and checkpoints

### S3 Buckets
- `company-aurora-logs-poc`: Aurora error and slowquery logs (OpenObserve format)
- `aurora-k8s-logs-072006186126`: Kubernetes pod logs

### IAM Roles
- `aurora-discovery-task-role`: RDS API access for discovery
- `aurora-processor-task-role`: RDS log download access
- `aurora-logs-eks-admin-role`: EKS cluster management

## Key Design Decisions

### Cost Optimization
1. **Bypass CloudWatch**: Direct RDS API access eliminates CloudWatch ingestion costs
2. **Single Kafka Node**: Sufficient for log metadata queue
3. **Valkey Caching**: Reduces RDS API calls (API rate limits)
4. **S3 Storage**: OpenObserve uses efficient columnar format in S3
5. **Single EKS Node**: t4g.2xlarge handles the workload

### Log Filtering
- **Only Error and Slow Query Logs**: General logs are filtered out
- **At Fluent Bit Layer**: Reduces processing and storage costs
- **Grep Filter**: `log_type` must be "error" or "slowquery"

### Scaling Strategy
- **Discovery Service**: Single instance with 5-minute polling interval
- **Processor Service**: Can scale based on queue depth
- **Fluent Bit**: DaemonSet ensures one per node
- **Kafka**: Single node (no replication needed for POC)

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

2. **Processor Extraction**: Downloads log with timestamp intact via RDS API

3. **Fluent Bit Parsing**: 
   - Parser extracts timestamp: `2025-08-03 15:30:45`
   - Lua script converts to milliseconds: `1754235045000`
   - Sets `_timestamp` field for OpenObserve

4. **OpenObserve Storage**: 
   - Uses `_timestamp` field (not ingestion time)
   - Log appears at exact Aurora generation time
   - Searchable by original timestamp

### Configuration
```yaml
# Fluent Bit parser preserves timestamp
Time_Key          timestamp
Time_Format       %Y-%m-%d %H:%M:%S
Time_Keep         On

# Lua script ensures OpenObserve compatibility
record["_timestamp"] = timestamp_ms
```

## Metrics & Dashboards

### OTEL Collector Configuration
- Scrapes Prometheus metrics from all services
- Exports to OpenObserve via Prometheus RemoteWrite
- Metrics appear in OpenObserve dashboards

### Available Metrics
1. **Service Health**
   - Pod status and restarts
   - CPU and memory usage
   - Network I/O

2. **Processing Metrics**
   - Logs processed per minute
   - Processing lag (current time - log time)
   - Error rates by service

3. **Queue Metrics**
   - Kafka topic lag
   - Messages pending
   - Consumer group status

### OpenObserve Dashboards
- **System Overview**: All services health at a glance
- **Processing Dashboard**: Log processing rates and latency
- **Error Dashboard**: Failed processing and error trends

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
- EKS cluster security group
- Node security group (allows internal communication)

### Cost Comparison

**CloudWatch Logs (Current)**:
- Ingestion: $0.50/GB × ~1TB/day × 30 days = $15,000/month
- Storage: $0.03/GB × ~30TB = $900/month  
- Queries: $0.005/GB scanned
- **Total**: ~$16,000+/month

**Aurora Log System (New)**:
- EKS: t4g.2xlarge = ~$200/month
- S3 Storage: $0.023/GB × ~30TB = $690/month
- DynamoDB: ~$50/month
- API calls: Minimal
- **Total**: ~$1,000/month

**Savings**: ~94% reduction in logging costs