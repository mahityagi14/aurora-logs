# Phase 2: Database Infrastructure Setup for EKS - Console Guide (2025)

## Overview
This phase covers setting up the database infrastructure including Aurora MySQL, DynamoDB tables, Valkey (ElastiCache), and ECR repository through AWS Console. All configurations use public subnets for simplified POC deployment. These services will be accessed by EKS pods using the node group IAM role permissions configured in Phase 1.

**Key Updates for 2025:**
- Aurora MySQL now supports Graviton 4 (R8g instances) with up to 40% performance improvement
- DynamoDB on-demand is now the default and recommended mode
- ElastiCache Valkey offers 20% lower pricing than Redis OSS
- All services optimized for ARM/Graviton architectures

## POC vs Production Configuration Summary

| Component | POC Configuration | Production Configuration | Monthly Cost Difference |
|-----------|------------------|-------------------------|------------------------|
| **Aurora MySQL** | 2x db.r8g.large (2 vCPU, 16GB) | 2x db.r8g.8xlarge (32 vCPU, 256GB) | $176 vs $4,600 |
| **DynamoDB** | On-demand mode | On-demand mode (same) | <$5 vs $500-1000 |
| **ElastiCache Valkey** | 2x cache.r6g.large (2 vCPU, 13GB) | 3x cache.r6g.4xlarge (16 vCPU, 105GB) | $230 vs $3,750 |
| **ECR** | Single repository | Multi-region replication | $1 vs $50 |
| **ALB** | Internet-facing, no WAF | Internet-facing + WAF | $25 vs $150 |
| **Total Phase 2** | ~$437/month | ~$10,050/month | 23x increase |

## Variable Placeholders Reference
Continuing from Phase 1, these placeholders are used:

| Placeholder | Description | Source |
|------------|-------------|---------|
| [region] | Your AWS region | Phase 1 |
| [account-id] | Your 12-digit AWS account ID | Phase 1 |
| [vpc-id] | Your existing VPC ID | Phase 1 |
| [public-subnet-1] | First public subnet ID | Phase 1 |
| [public-subnet-2] | Second public subnet ID | Phase 1 |
| [public-subnet-3] | Third public subnet ID | Phase 1 |
| [cache-id] | ElastiCache cluster ID | Generated in this phase |

## Step 1: Create DynamoDB Tables

### DynamoDB Configuration Comparison

| Setting | POC Configuration | Production Configuration | Rationale |
|---------|------------------|-------------------------|-----------|
| **Capacity Mode** | On-demand | On-demand | Default mode, auto-scales |
| **Point-in-time Recovery** | Disabled | Enabled | Production data protection |
| **Global Tables** | Single region | Multi-region | Disaster recovery |
| **Contributor Insights** | Disabled | Enabled | Performance monitoring |
| **Deletion Protection** | Disabled | Enabled | Prevent accidental deletion |
| **Encryption** | AWS managed | Customer managed (CMK) | Compliance requirements |

### 1.1 Aurora Instance Metadata Table

**Purpose**: Stores RDS cluster and instance metadata discovered by the discovery service. Reduces RDS API calls by caching instance information.

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-instance-metadata`
   - Partition key: `pk` (String) - Will store "CLUSTER#cluster-id" or "INSTANCE#instance-id"
   - Sort key: `sk` (String) - Will store "METADATA"
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand** (2025 default)
4. Expand **Additional settings**:
   - Enable **Time to Live (TTL)**
   - TTL attribute: `ttl`
5. Click **Create table**

**Usage Pattern**: 
- Written by: Discovery service when finding new RDS instances
- Read by: API endpoints for operational visibility
- TTL: Set to 7 days for automatic cleanup of stale instance data

### 1.2 Aurora Log File Tracking Table

**Purpose**: Maintains processing state for each log file to prevent duplicate processing and track progress. Critical for maintaining exactly-once processing semantics.

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-log-file-tracking`
   - Partition key: `instance_id` (String)
   - Sort key: `log_file_name` (String)
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand**
4. **No TTL for this table** - Processing state must be maintained indefinitely
5. Click **Create table**

**Usage Pattern**:
- Read by: Discovery service to check if logs are new (comparing last_written timestamps)
- Written by: Processor service to update processing position (last_marker, processed_size)
- No TTL: State must persist to prevent reprocessing

### 1.3 Aurora Log Processing Jobs Table

**Purpose**: Tracks individual log processing jobs for operational visibility, debugging, and performance monitoring. Provides audit trail of all processing activities.

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-log-processing-jobs`
   - Partition key: `pk` (String) - Will store "JOB#job-id" or "DATE#yyyy-mm-dd"
   - Sort key: `sk` (String) - Will store "METADATA" or "TIME#hh:mm:ss#job-id"
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand**
4. Expand **Additional settings**:
   - Enable **Time to Live (TTL)**
   - TTL attribute: `ttl`
5. Click **Create table**

**Usage Pattern**:
- Written by: Processor service when starting and completing jobs
- Read by: API endpoints for job status and statistics
- TTL: Set to 30 days for automatic cleanup of old job records

**Note**: DynamoDB on-demand mode is recommended for workloads with unpredictable traffic patterns. It automatically scales and you only pay for what you use.

## Step 2: Create Aurora MySQL Cluster

### Aurora MySQL Configuration Comparison

| Setting | POC Configuration | Production Configuration | Performance Impact |
|---------|------------------|-------------------------|-------------------|
| **Instance Type** | db.r8g.large (Graviton 4) | db.r8g.8xlarge (Graviton 4) | 16x compute capacity |
| **Multi-AZ** | 2 instances | 3+ instances + global database | Higher availability |
| **Backup Retention** | 1 day | 35 days | Full recovery capability |
| **Performance Insights** | 7 days | 2 years | Historical analysis |
| **Enhanced Monitoring** | Disabled | 1-second granularity | Real-time metrics |
| **Deletion Protection** | Disabled | Enabled | Prevent accidents |

### 2.1 Create DB Subnet Group

1. Navigate to **RDS Console** → **Subnet groups** → **Create DB subnet group**
2. **Subnet group details**:
   - Name: `aurora-mysql-subnet-group`
   - Description: `Subnet group for Aurora MySQL POC`
   - VPC: [vpc-id]
3. **Add subnets**:
   - Availability Zones: Select all 3 AZs
   - Subnets: Select your public subnets:
     - [public-subnet-1]
     - [public-subnet-2]
     - [public-subnet-3]
4. Click **Create**

### 2.2 Create Cluster Parameter Group

1. Navigate to **Parameter groups** → **Create parameter group**
2. **Parameter group details**:
   - Parameter group family: `aurora-mysql8.0`
   - Type: **DB cluster parameter group**
   - Group name: `aurora-mysql80-logs-poc`
   - Description: `Aurora MySQL 8.0 cluster parameters for log POC`
3. Click **Create**
4. Click on the parameter group name → **Edit parameters**
5. Search and modify these parameters:

| Parameter | POC Value | Production Value | Description |
|-----------|-----------|------------------|-------------|
| slow_query_log | 1 | 1 | Enable slow query logging |
| long_query_time | 1 | 0.1 | POC: >1s, Prod: >100ms |
| log_queries_not_using_indexes | 1 | 1 | Log unindexed queries |
| log_throttle_queries_not_using_indexes | 300 | 60 | Throttle per minute |
| log_output | FILE | FILE | Output logs to files |
| log_error_verbosity | 3 | 3 | Maximum error detail |
| innodb_print_all_deadlocks | 1 | 1 | Log all deadlocks |
| log_slow_admin_statements | 1 | 1 | Include admin queries |
| log_slow_replica_statements | 1 | 1 | Include replica queries |

6. Click **Save changes**

### 2.3 Create DB Parameter Group

1. Navigate to **Parameter groups** → **Create parameter group**
2. **Parameter group details**:
   - Parameter group family: `aurora-mysql8.0`
   - Type: **DB parameter group**
   - Group name: `aurora-mysql80-instance-poc`
   - Description: `Aurora MySQL 8.0 instance parameters`
3. Click **Create**
4. Click on the parameter group name → **Edit parameters**
5. Search and modify:
   - `performance_schema`: **0** (POC: save memory) / **1** (Production)
   - `innodb_monitor_enable`: **all**
6. Click **Save changes**

### 2.4 Create Aurora Cluster

1. Navigate to **Databases** → **Create database**
2. **Choose a database creation method**: **Standard create**
3. **Engine options**:
   - Engine type: **Amazon Aurora**
   - Edition: **Amazon Aurora MySQL-Compatible Edition**
   - Engine version: **Aurora MySQL 3.08.0 (compatible with MySQL 8.0.39)**
4. **Templates**: **Dev/Test**
5. **Settings**:
   - DB cluster identifier: `aurora-mysql-poc-01`
   - Master username: `admin`
   - Master password: **Choose a strong password** (save this!)
   - Confirm password: **Re-enter password**
6. **Instance configuration**:
   - DB instance class: **Memory optimized classes (includes R classes)**
   - Select: **db.r8g.large** (Graviton 4, 2 vCPUs, 16 GiB RAM)
   
   **Production Alternative**: db.r8g.8xlarge (32 vCPUs, 256 GiB RAM)
   
7. **Availability & durability**:
   - Multi-AZ deployment: **Create an Aurora Replica in a different AZ**
8. **Connectivity**:
   - Virtual private cloud (VPC): [vpc-id]
   - DB subnet group: `aurora-mysql-subnet-group`
   - Public access: **Yes** (for POC simplicity)
   - VPC security group: **Choose existing**
   - Existing VPC security groups: Select `aurora-mysql-sg` (remove default)
   - Database port: **3306**
9. **Database authentication**: **Password authentication**
10. Expand **Additional configuration**:
    - Initial database name: `mydb`
    - DB cluster parameter group: `aurora-mysql80-logs-poc`
    - DB parameter group: `aurora-mysql80-instance-poc`
    - Backup retention period: **1 day** (POC) / **35 days** (Production)
    - Enable deletion protection: **No** (POC) / **Yes** (Production)
11. Click **Create database**

**Note**: Database creation takes 10-15 minutes. Continue with other steps while it creates.

## Step 3: Create Valkey (ElastiCache) Cluster

**Purpose**: Valkey is used to cache RDS API responses, reducing API calls by 70-90%. The discovery service caches cluster and instance information to minimize rate limit impact when discovering logs across 316 RDS instances.

### ElastiCache Valkey Configuration Comparison

| Setting | POC Configuration | Production Configuration | Cost Impact |
|---------|------------------|-------------------------|-------------|
| **Engine** | Valkey 8 | Valkey 8 | 20% cheaper than Redis |
| **Node Type** | cache.r6g.large (Graviton 2) | cache.r6g.4xlarge | 8x memory capacity |
| **Replicas** | 1 | 2 per shard | Higher availability |
| **Multi-AZ** | Enabled | Enabled + auto-failover | Same best practice |
| **Cluster Mode** | Disabled | Enabled (3 shards) | Horizontal scaling |
| **Backup** | 1 day retention | 35 days | Recovery options |

### 3.1 Create Cache Subnet Group

1. Navigate to **ElastiCache Console** → **Subnet groups** → **Create subnet group**
2. **Subnet group settings**:
   - Name: `aurora-cache-subnet-group`
   - Description: `Subnet group for Valkey cache`
   - VPC ID: [vpc-id]
3. **Availability Zones**: Select your public subnets:
   - [public-subnet-1]
   - [public-subnet-2]
   - [public-subnet-3]
4. Click **Create**

### 3.2 Create Valkey Cluster

1. Navigate to **Redis OSS caches** → **Create Redis OSS cache**
2. **Deployment option**: **Design your own cache**
3. **Creation method**: **Easy create**
4. **Configuration**:
   - Configuration name: **aurora-log-cache-poc**
   - **Engine**: Select **Valkey 8** (20% cheaper than Redis OSS)
   - Node type: **cache.r6g.large** (Graviton 2, 13.07 GiB)
   
   **Production Alternative**: cache.r6g.4xlarge (105.81 GiB)
   
   - Number of replicas: **1**
   - Multi-AZ: **Enable**
5. **Subnet group settings**:
   - Choose existing subnet group: `aurora-cache-subnet-group`
6. Click **Next**
7. **Security**:
   - Security groups: Select `valkey-cluster-sg` (remove default)
   - Encryption at-rest: **Enable**
   - Encryption in-transit: **Disable** (POC) / **Enable** (Production)
8. **Backup and maintenance**:
   - Enable automatic backups: **Yes**
   - Backup retention period: **1 day** (POC) / **35 days** (Production)
9. Click **Next** → Review settings → **Create**

**Note**: Cluster creation takes 5-10 minutes. Note the [cache-id] portion of the endpoint when created.

## Step 4: Create ECR Repository

### ECR Configuration Comparison

| Setting | POC Configuration | Production Configuration | Security Impact |
|---------|------------------|-------------------------|-----------------|
| **Scan on Push** | Basic scanning | Enhanced scanning | Vulnerability detection |
| **Immutability** | Disabled | Enabled | Prevent overwrites |
| **Lifecycle Policy** | Keep 10 images | Keep 30 images | Storage optimization |
| **Replication** | Single region | Multi-region | Disaster recovery |
| **Encryption** | AES-256 | Customer managed KMS | Compliance |

1. Navigate to **ECR Console** → **Repositories** → **Create repository**
2. **General settings**:
   - Visibility settings: **Private**
   - Repository name: `aurora-log-system`
3. **Image scan settings**:
   - Scan on push: **Enable**
   - Scanning configuration: **Basic scanning** (POC) / **Enhanced scanning** (Production)
4. **Encryption settings**:
   - Encryption configuration: **AES-256**
5. Click **Create repository**

### 4.1 Note ECR Repository URI

After creation:
1. Click on the repository name `aurora-log-system`
2. Copy the **URI** (format: `[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system`)
3. Save this for Phase 3 and Jenkins configuration

## Step 5: Create Application Load Balancer

### ALB Configuration Comparison

| Setting | POC Configuration | Production Configuration | Availability Impact |
|---------|------------------|-------------------------|-------------------|
| **Type** | Application Load Balancer | Application Load Balancer | Same |
| **Scheme** | Internet-facing | Internet-facing | Same |
| **IP Type** | IPv4 | Dualstack (IPv4 + IPv6) | Broader access |
| **Zones** | 3 AZs | 3+ AZs | Same/Higher |
| **WAF** | Disabled | Enabled with rules | Security |
| **Access Logs** | Disabled | Enabled to S3 | Audit trail |

### 5.1 Create Target Group First

1. Navigate to **EC2 Console** → **Target Groups** → **Create target group**
2. **Basic configuration**:
   - Target type: **IP addresses**
   - Target group name: `openobserve-tg`
   - Protocol: **HTTP**
   - Port: **5080**
   - VPC: [vpc-id]
   - Protocol version: **HTTP1**
3. **Health checks**:
   - Health check protocol: **HTTP**
   - Health check path: `/healthz`
   - Advanced health check settings:
     - Healthy threshold: **2**
     - Unhealthy threshold: **3**
     - Timeout: **5** seconds
     - Interval: **30** seconds
     - Success codes: **200**
4. Click **Next**
5. Skip registering targets (will be done automatically by AWS Load Balancer Controller)
6. Click **Create target group**

### 5.2 Create Load Balancer

1. Navigate to **Load Balancers** → **Create load balancer**
2. **Select load balancer type**: **Application Load Balancer** → **Create**
3. **Basic configuration**:
   - Load balancer name: `openobserve-alb`
   - Scheme: **Internet-facing**
   - IP address type: **IPv4**
4. **Network mapping**:
   - VPC: [vpc-id]
   - Mappings: Select all 3 availability zones with public subnets:
     - AZ 1: [public-subnet-1]
     - AZ 2: [public-subnet-2]
     - AZ 3: [public-subnet-3]
5. **Security groups**: 
   - Remove default
   - Select `alb-sg`
6. **Listeners and routing**:
   - Protocol: **HTTP**
   - Port: **80**
   - Default action: Forward to `openobserve-tg`
7. Click **Create load balancer**

### 5.3 Note ALB DNS Name

After creation:
1. The ALB DNS name will be shown (format: `openobserve-alb-[xxx].[region].elb.amazonaws.com`)
2. Save this for later access to OpenObserve UI

## Step 6: Gather Endpoints for Phase 3 & 4

After all resources are created, collect these endpoints:

1. **Aurora Endpoints** (RDS Console → Your cluster):
   - Writer endpoint: `aurora-mysql-poc-01.cluster-[xxx].[region].rds.amazonaws.com`
   - Reader endpoint: `aurora-mysql-poc-01.cluster-ro-[xxx].[region].rds.amazonaws.com`

2. **Valkey Endpoint** (ElastiCache Console → Your cluster):
   - Primary endpoint: `aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com:6379`
   - **Important**: Note the [cache-id] portion for Phase 3 & 4 configurations

3. **ECR Repository URI**:
   - `[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system`

4. **ALB DNS Name**:
   - `openobserve-alb-[xxx].[region].elb.amazonaws.com`