# Phase 2: Database Infrastructure Setup - Updated Console Guide

## Overview
This phase covers setting up the database infrastructure including Aurora MySQL, DynamoDB tables, Valkey (ElastiCache), and ECR repository through AWS Console. All configurations use public subnets for simplified POC deployment.

**Key Update in this phase:**
- ⚠️ **Upgraded to Valkey 8.1** for better performance (10% throughput improvement, 20% memory reduction, Bloom filter support)

## Step 1: Create DynamoDB Tables

### 1.1 Aurora Instance Metadata Table

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-instance-metadata`
   - Partition key: `cluster_id` (String)
   - Sort key: `instance_id` (String)
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand**
4. Expand **Secondary indexes** → Click **Create global secondary index**:
   - Partition key: `status` (String)
   - Sort key: `last_discovered` (String)
   - Index name: `status-index`
   - Projection: **All**
5. Scroll down and keep other settings as default
6. Click **Create table**

### 1.2 Aurora Log File Tracking Table

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-log-file-tracking`
   - Partition key: `instance_id` (String)
   - Sort key: `log_file_name` (String)
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand**
4. Expand **Secondary indexes** → Click **Create global secondary index**:
   - Partition key: `processing_status` (String)
   - Sort key: `last_modified` (Number)
   - Index name: `processing-status-index`
   - Projection: **All**
5. Expand **Additional settings**:
   - Enable **Time to Live (TTL)**
   - TTL attribute: `ttl`
6. Click **Create table**

### 1.3 Aurora Log Processing Jobs Table

1. Navigate to **DynamoDB Console** → **Tables** → **Create table**
2. **Table details**:
   - Table name: `aurora-log-processing-jobs`
   - Partition key: `job_id` (String)
   - Sort key: `created_at` (String)
3. **Table settings**:
   - Settings: **Customize settings**
   - Table class: **DynamoDB Standard**
   - Read/write capacity settings: **On-demand**
4. Expand **Additional settings**:
   - Enable **Time to Live (TTL)**
   - TTL attribute: `ttl`
5. Click **Create table**

## Step 2: Create Aurora MySQL Cluster

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

| Parameter | Value | Description |
|-----------|-------|-------------|
| slow_query_log | 1 | Enable slow query logging |
| long_query_time | 1 | Log queries > 1 second |
| log_queries_not_using_indexes | 1 | Log unindexed queries |
| log_throttle_queries_not_using_indexes | 300 | Throttle per minute |
| log_output | FILE | Output logs to files |
| log_error_verbosity | 3 | Maximum error detail |
| innodb_print_all_deadlocks | 1 | Log all deadlocks |
| log_slow_admin_statements | 1 | Include admin queries |
| log_slow_replica_statements | 1 | Include replica queries |

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
   - `performance_schema`: **0** (disable to save memory)
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
   - DB instance class: **Burstable classes**
   - Select: **db.t4g.medium** (2 vCPUs, 4 GiB RAM)
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
    - **Enable CloudWatch Logs exports**:
      - ✓ Error log
      - ✓ Slow query log
    - Backup retention period: **1 day**
    - Enable deletion protection: **No** (for POC)
11. Click **Create database**

**Note**: Database creation takes 10-15 minutes. Continue with other steps while it creates.

## Step 3: Create Valkey (ElastiCache) Cluster - UPDATED

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

### 3.2 Create Valkey 8.1 Cluster - UPDATED

**Important Update**: We're now using Valkey 8.1 which provides:
- Native Bloom filter support (98% less memory for lookups)
- 10% throughput improvement with pipelining
- 20% memory reduction for key/value patterns
- COMMANDLOG feature for better observability

1. Navigate to **Redis OSS caches** → **Create Redis OSS cache**
2. **Deployment option**: **Design your own cache**
3. **Creation method**: **Easy create**
4. **Configuration**:
   - Configuration name: **aurora-log-cache-poc**
   - **Engine version**: **8.1** (Valkey 8.1 - Latest)
   - Node type: **cache.t4g.micro** (0.5 GiB)
   - Number of replicas: **1**
   - Multi-AZ: **Enable**
5. **Subnet group settings**:
   - Choose existing subnet group: `aurora-cache-subnet-group`
6. Click **Next**
7. **Security**:
   - Security groups: Select `valkey-cluster-sg` (remove default)
   - Encryption at-rest: **Enable**
   - Encryption in-transit: **Disable** (for POC simplicity)
8. **Logs**:
   - Slow log: **Enable**
   - Slow log destination: **CloudWatch Logs**
   - Log format: **JSON**
   - **NEW - Command log**: **Enable** (Valkey 8.1 feature)
   - Command log destination: **CloudWatch Logs**
9. **Backup and maintenance**:
   - Enable automatic backups: **Yes**
   - Backup retention period: **1 day**
10. **Advanced Valkey 8.1 settings** (if available):
    - Enable Bloom filter module: **Yes**
    - Hash table optimization: **Enable**
11. Click **Next** → Review settings → **Create**

**Note**: Cluster creation takes 5-10 minutes. The new Valkey 8.1 features will be automatically available once the cluster is ready.

## Step 4: Create ECR Repository

1. Navigate to **ECR Console** → **Repositories** → **Create repository**
2. **General settings**:
   - Visibility settings: **Private**
   - Repository name: `aurora-log-system`
3. **Image scan settings**:
   - Scan on push: **Enable**
   - Scan frequency: **Continuous scanning - scan on push**
4. **Encryption settings**:
   - Encryption configuration: **AES-256**
5. Click **Create repository**

### 4.1 Note ECR Repository URI

After creation:
1. Click on the repository name `aurora-log-system`
2. Copy the **URI** (format: `[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system`)
3. Save this for Phase 3

## Step 5: Create Application Load Balancer

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
5. Skip registering targets (will be done automatically by ECS)
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

2. **Valkey 8.1 Endpoint** (ElastiCache Console → Your cluster):
   - Primary endpoint: `aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com:6379`
   - Note the [cache-id] portion for Phase 4
   - **Verify version**: Check that it shows "Engine Version: 8.1" in the console

3. **ECR Repository URI**:
   - `[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system`

4. **ALB DNS Name**:
   - `openobserve-alb-[xxx].[region].elb.amazonaws.com`

## Step 7: Verify Infrastructure

### Test Aurora MySQL Connection:
```bash
# From CloudShell or local machine with MySQL client
mysql -h aurora-mysql-poc-01.cluster-[xxx].[region].rds.amazonaws.com \
  -u admin -p --ssl-mode=DISABLED

# Once connected, verify logging is enabled
SHOW VARIABLES LIKE 'slow_query_log';
SHOW VARIABLES LIKE 'log_output';
```

### Test Valkey 8.1 Connection:
```bash
# Install redis-cli if needed
sudo yum install -y redis

# Test connection (from an EC2 instance in the same VPC)
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com ping

# Verify Valkey 8.1 version
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com INFO server | grep version

# Test Bloom filter support (Valkey 8.1 feature)
redis-cli -h aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com
> BF.ADD mybloom item1
> BF.EXISTS mybloom item1
```

### Verify DynamoDB Tables:
```bash
# From CloudShell
aws dynamodb list-tables --query "TableNames[?contains(@, 'aurora')]"

# Should return:
# [
#     "aurora-instance-metadata",
#     "aurora-log-file-tracking",
#     "aurora-log-processing-jobs"
# ]
```

## Summary of Created Resources

After completing Phase 2, you should have:

### DynamoDB Tables:
- `aurora-instance-metadata` with status-index GSI
- `aurora-log-file-tracking` with processing-status-index GSI and TTL
- `aurora-log-processing-jobs` with TTL

### Aurora MySQL:
- 1 Aurora MySQL 8.0 cluster with 2 instances
- Configured for slow query and error logging
- CloudWatch logs export enabled

### Valkey Cache (UPDATED):
- 1 Redis-compatible cache cluster running **Valkey 8.1**
- Multi-AZ enabled
- New features: Bloom filters, improved performance, COMMANDLOG

### ECR:
- 1 repository: `aurora-log-system`

### Load Balancing:
- 1 Target Group: `openobserve-tg`
- 1 Application Load Balancer: `openobserve-alb`

## Next Steps
Proceed to Phase 3 to create the custom ECS-optimized AMI and build container images for all services.

## Change Summary for Phase 2

**Updated Components:**
1. **Valkey upgraded from 7.2 to 8.1**:
   - Added Bloom filter support for memory-efficient lookups
   - 10% throughput improvement with pipelining
   - 20% memory reduction for common patterns
   - New COMMANDLOG feature for better debugging
   - Hash table optimization for better performance