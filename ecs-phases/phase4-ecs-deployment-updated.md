# Phase 4: ECS Cluster Creation and Service Deployment - Updated Guide

## Overview
This phase covers creating the ECS cluster, setting up EFS for persistent storage, creating task definitions, deploying all services, and configuring the complete system.

**Key Updates in this phase:**
- ⚠️ **Added explicit ARM64 runtime platform** to all task definitions
- ⚠️ **Added non-blocking log mode** with buffer configuration
- ✅ **EC2 launch type only** (already configured correctly)

## Step 1: Create ECS Cluster

**Important Note about EBS Storage**: 
- Data stored in host paths (`/data/kafka`, `/data/openobserve`) persists only on the specific EC2 instance
- If an instance is terminated, the data is lost
- For production, implement regular backups or use AWS Backup for EBS volumes
- Consider using dedicated EBS volumes attached to instances for better data persistence

### 1.1 Create Cluster

1. Navigate to **ECS Console** → **Clusters** → **Create cluster**
2. **Cluster configuration**:
   - Cluster name: `aurora-logs-poc-cluster`
3. **Infrastructure**:
   - ✓ **Amazon EC2 instances**
   - ☐ **AWS Fargate (serverless)** - Leave unchecked
4. For **Amazon EC2 instances**:
   - Operating system/Architecture: **Amazon Linux 2023 / ARM64**
   - EC2 instance type: **t4g.medium**
   - Desired capacity:
     - Minimum: **2**
     - Maximum: **10**
     - Desired: **3**
   - SSH Key pair: Select your key pair
5. **Storage**:
   - Root volume type: **gp3**
   - Root volume size: **100 GiB** (increased for container storage)
6. **Network settings**:
   - VPC: [vpc-id]
   - Subnets: Select all 3 public subnets
   - Security group: Select `ecs-instances-sg`
   - Auto-assign public IP: **Turn on**
7. **Monitoring**:
   - ✓ Use Container Insights
8. Click **Create**

### 1.2 Configure Auto Scaling

After cluster creation:
1. Go to **Capacity providers** tab
2. Click on the auto scaling group link
3. **Edit** the auto scaling group:
   - Instance types: Add `t4g.large`, `t4g.xlarge`
   - Enable **Capacity Rebalancing**

## Step 2: Create Task Definitions - UPDATED

### 2.1 Kafka Task Definition - UPDATED

1. Navigate to **ECS Console** → **Task definitions** → **Create new task definition**
2. Click **Create new task definition with JSON**
3. Replace with this JSON (substitute placeholders):

```json
{
  "family": "kafka-task",
  "taskRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-task-role",
  "executionRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-execution-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "2048",
  "memory": "4096",
  "runtimePlatform": {
    "operatingSystemFamily": "LINUX",
    "cpuArchitecture": "ARM64"
  },
  "volumes": [
    {
      "name": "kafka-data",
      "host": {
        "sourcePath": "/data/kafka"
      }
    }
  ],
  "containerDefinitions": [
    {
      "name": "kafka",
      "image": "[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system:kafka-latest",
      "cpu": 2048,
      "memory": 4096,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 9092,
          "protocol": "tcp"
        },
        {
          "containerPort": 9093,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "KAFKA_HEAP_OPTS",
          "value": "-Xmx3G -Xms3G"
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "kafka-data",
          "containerPath": "/var/kafka-data"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "mode": "non-blocking",
        "options": {
          "awslogs-group": "/ecs/apache-kafka",
          "awslogs-region": "[region]",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true",
          "max-buffer-size": "25m"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "kafka-broker-api-versions.sh --bootstrap-server localhost:9092 || exit 1"],
        "interval": 30,
        "timeout": 10,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

4. Click **Create**

### 2.2 OpenObserve Task Definition - UPDATED

Create with JSON:

```json
{
  "family": "openobserve-task",
  "taskRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-task-role",
  "executionRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-execution-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "2048",
  "memory": "4096",
  "runtimePlatform": {
    "operatingSystemFamily": "LINUX",
    "cpuArchitecture": "ARM64"
  },
  "volumes": [
    {
      "name": "openobserve-data",
      "host": {
        "sourcePath": "/data/openobserve"
      }
    }
  ],
  "containerDefinitions": [
    {
      "name": "openobserve",
      "image": "[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system:openobserve-latest",
      "cpu": 2048,
      "memory": 4096,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 5080,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "AWS_REGION",
          "value": "[region]"
        },
        {
          "name": "ZO_ROOT_USER_EMAIL",
          "value": "admin@poc.com"
        },
        {
          "name": "ZO_ROOT_USER_PASSWORD",
          "value": "admin123"
        },
        {
          "name": "ZO_S3_BUCKET_NAME",
          "value": "company-aurora-logs-poc"
        }
      ],
      "mountPoints": [
        {
          "sourceVolume": "openobserve-data",
          "containerPath": "/data"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "mode": "non-blocking",
        "options": {
          "awslogs-group": "/ecs/openobserve",
          "awslogs-region": "[region]",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true",
          "max-buffer-size": "25m"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:5080/healthz || exit 1"],
        "interval": 30,
        "timeout": 3,
        "retries": 3,
        "startPeriod": 10
      }
    }
  ]
}
```

### 2.3 Discovery Task Definition - UPDATED

Create with JSON:

```json
{
  "family": "discovery-task",
  "taskRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-task-role",
  "executionRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-execution-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "1024",
  "memory": "2048",
  "runtimePlatform": {
    "operatingSystemFamily": "LINUX",
    "cpuArchitecture": "ARM64"
  },
  "containerDefinitions": [
    {
      "name": "discovery",
      "image": "[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system:discovery-latest",
      "cpu": 1024,
      "memory": 2048,
      "essential": true,
      "environment": [
        {
          "name": "KAFKA_BROKERS",
          "value": "kafka-service.aurora-poc:9092"
        },
        {
          "name": "INSTANCE_TABLE",
          "value": "aurora-instance-metadata"
        },
        {
          "name": "TRACKING_TABLE",
          "value": "aurora-log-file-tracking"
        },
        {
          "name": "VALKEY_URL",
          "value": "redis://aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com:6379"
        },
        {
          "name": "LOG_LEVEL",
          "value": "INFO"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "mode": "non-blocking",
        "options": {
          "awslogs-group": "/ecs/aurora-log-discovery",
          "awslogs-region": "[region]",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true",
          "max-buffer-size": "25m"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "./discovery -health"],
        "interval": 30,
        "timeout": 3,
        "retries": 3,
        "startPeriod": 5
      }
    }
  ]
}
```

### 2.4 Processor Task Definition - UPDATED

Create with JSON:

```json
{
  "family": "processor-task",
  "taskRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-task-role",
  "executionRoleArn": "arn:aws:iam::[account-id]:role/aurora-ecs-execution-role",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "2048",
  "memory": "4096",
  "runtimePlatform": {
    "operatingSystemFamily": "LINUX",
    "cpuArchitecture": "ARM64"
  },
  "containerDefinitions": [
    {
      "name": "processor",
      "image": "[account-id].dkr.ecr.[region].amazonaws.com/aurora-log-system:processor-latest",
      "cpu": 2048,
      "memory": 4096,
      "essential": true,
      "environment": [
        {
          "name": "KAFKA_BROKERS",
          "value": "kafka-service.aurora-poc:9092"
        },
        {
          "name": "S3_BUCKET",
          "value": "company-aurora-logs-poc"
        },
        {
          "name": "TRACKING_TABLE",
          "value": "aurora-log-file-tracking"
        },
        {
          "name": "JOBS_TABLE",
          "value": "aurora-log-processing-jobs"
        },
        {
          "name": "CONSUMER_GROUP",
          "value": "aurora-processor-group"
        },
        {
          "name": "LOG_LEVEL",
          "value": "INFO"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "mode": "non-blocking",
        "options": {
          "awslogs-group": "/ecs/aurora-log-processor",
          "awslogs-region": "[region]",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true",
          "max-buffer-size": "25m"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "./processor -health"],
        "interval": 30,
        "timeout": 3,
        "retries": 3,
        "startPeriod": 5
      }
    }
  ]
}
```

## Step 3: Configure ECS Instance User Data

Before deploying services, ensure ECS instances have the necessary directories:

1. Navigate to **EC2 Console** → **Auto Scaling Groups**
2. Find the auto scaling group created by ECS cluster
3. **Edit** → **Advanced configurations** → **User data**
4. Add this script:

```bash
#!/bin/bash
# Create directories for container data
mkdir -p /data/kafka
mkdir -p /data/openobserve

# Set permissions
chmod 755 /data
chmod 755 /data/kafka
chmod 755 /data/openobserve

# For existing instances, SSH and run these commands manually
```

## Step 4: Create Service Discovery Namespace

1. Navigate to **AWS Cloud Map Console** → **Namespaces** → **Create namespace**
2. **Namespace configuration**:
   - Namespace name: `aurora-poc`
   - Namespace description: `Service discovery for Aurora POC`
   - Instance discovery: **API calls and DNS queries in VPCs**
   - VPC: [vpc-id]
3. **DNS configuration**:
   - TTL: **60** seconds
4. Click **Create namespace**

## Step 5: Deploy Services

### 5.1 Deploy Kafka Service (First)

**Note**: When using EBS volumes with host paths, Kafka data persists only on the specific EC2 instance. For production, consider using EBS snapshots for backup.

1. Navigate to **ECS Console** → **Clusters** → `aurora-logs-poc-cluster`
2. **Services** tab → **Create**
3. **Environment**:
   - Compute configuration: **Launch type**
   - Launch type: **EC2**
4. **Deployment configuration**:
   - Application type: **Service**
   - Task definition: **kafka-task**
   - Revision: **Latest**
   - Service name: `kafka-service`
   - Service type: **Replica**
   - Desired tasks: **1**
5. **Deployment options**:
   - Deployment type: **Rolling update**
   - Min running tasks: **100%**
   - Max running tasks: **200%**
6. **Task Placement**:
   - Placement strategy: **AZ Balanced Spread**
   - Add placement constraint:
     - Type: **memberOf**
     - Expression: `attribute:ecs.instance-type == t4g.medium`
7. **Networking**:
   - VPC: [vpc-id]
   - Subnets: Select all public subnets
   - Security groups: `kafka-brokers-sg`
   - Public IP: **Turn on**
8. **Service discovery**:
   - ✓ Configure service discovery integration
   - Namespace: `aurora-poc`
   - Configure service discovery service: **Create new service discovery service**
   - Service discovery name: `kafka-service`
   - Enable ECS task health propagation: **Yes**
   - DNS record type: **A**
9. Click **Create**

Wait for Kafka service to become healthy before proceeding (2-3 minutes).

### 5.2 Initialize Kafka Topics

1. Find the Kafka task in **Tasks** tab
2. Click on the task ID
3. Note the public IP address
4. SSH to any ECS instance:
```bash
ssh -i your-key.pem ec2-user@[ecs-instance-public-ip]
```
5. Connect to Kafka container:
```bash
# Install Kafka client tools
sudo yum install -y java-17-amazon-corretto
wget https://downloads.apache.org/kafka/4.0.0/kafka_2.13-4.0.0.tgz
tar -xzf kafka_2.13-4.0.0.tgz
cd kafka_2.13-4.0.0

# Create topics (replace kafka-ip with actual IP)
bin/kafka-topics.sh --create \
    --bootstrap-server [kafka-public-ip]:9092 \
    --topic aurora-logs-slowquery \
    --partitions 10 \
    --replication-factor 1

bin/kafka-topics.sh --create \
    --bootstrap-server [kafka-public-ip]:9092 \
    --topic aurora-logs-error \
    --partitions 10 \
    --replication-factor 1

bin/kafka-topics.sh --create \
    --bootstrap-server [kafka-public-ip]:9092 \
    --topic aurora-logs-dlq \
    --partitions 3 \
    --replication-factor 1

# Verify topics
bin/kafka-topics.sh --list --bootstrap-server [kafka-public-ip]:9092
```

### 5.3 Deploy OpenObserve Service

1. Back in ECS Console → **Services** → **Create**
2. Follow similar steps as Kafka but:
   - Task definition: **openobserve-task**
   - Service name: `openobserve-service`
   - Security groups: `openobserve-sg`
   - Service discovery name: `openobserve-service`
   - Add placement constraint:
     - Type: **memberOf**
     - Expression: `attribute:ecs.instance-type == t4g.medium`
3. **Load balancing**:
   - Load balancer type: **Application Load Balancer**
   - Load balancer: `openobserve-alb`
   - Listener: **80:HTTP**
   - Target group: `openobserve-tg`
4. Click **Create**

### 5.4 Deploy Discovery Service

1. **Services** → **Create**
2. Configuration:
   - Task definition: **discovery-task**
   - Service name: `discovery-service`
   - Desired tasks: **1**
   - Security groups: `ecs-instances-sg`
   - Service discovery name: `discovery-service`
3. Click **Create**

### 5.5 Deploy Processor Service

1. **Services** → **Create**
2. Configuration:
   - Task definition: **processor-task**
   - Service name: `processor-service`
   - Desired tasks: **2**
   - Security groups: `ecs-instances-sg`
   - Service discovery name: `processor-service`
3. **Service auto scaling**:
   - ✓ Configure service auto scaling
   - Minimum tasks: **1**
   - Maximum tasks: **5**
4. Click **Create**
5. After creation, add scaling policy:
   - Go to service → **Auto scaling** tab → **Update**
   - Add policy:
     - Policy type: **Target tracking**
     - Policy name: `processor-cpu-scaling`
     - ECS service metric: **ECSServiceAverageCPUUtilization**
     - Target value: **70**
   - Click **Update**

## Step 6: Configure OpenObserve

### 6.1 Access OpenObserve UI

1. Get ALB DNS: `openobserve-alb-[xxx].[region].elb.amazonaws.com`
2. Open in browser: `http://[alb-dns]`
3. Login: `admin@poc.com` / `admin123`

### 6.2 Configure S3 Data Source

1. Navigate to **Ingestion** → **Data Sources** → **Add Data Source**
2. Select **Amazon S3**
3. Configure:
   - Name: `aurora-logs`
   - Bucket: `company-aurora-logs-poc`
   - Region: [region]
   - Prefix for slow queries: `slowquery/`
   - Prefix for errors: `error/`
   - File format: **TSV**
   - Compression: **GZIP**
4. Test connection and save

### 6.3 Create Log Streams

1. **Slow Query Stream**:
   - Go to **Logs** → **Streams** → **Create**
   - Name: `aurora-slowquery`
   - Source: S3 (aurora-logs)
   - Pattern: `slowquery/*`

2. **Error Log Stream**:
   - Name: `aurora-error`
   - Source: S3 (aurora-logs)
   - Pattern: `error/*`

### 6.4 Create Dashboards

1. **Slow Query Dashboard**:
   - **Metrics** → **Dashboards** → **Create**
   - Add panels:
     - Query time trends (line chart)
     - Top 10 slow queries (table)
     - Query count by database (pie chart)
     - Lock time analysis (histogram)

2. **Error Dashboard**:
   - Error frequency over time
   - Errors by severity level
   - Top error messages
   - Error distribution by thread

## Step 7: Test the System

### 7.1 Generate Test Data in Aurora

```sql
-- Connect to Aurora
mysql -h aurora-mysql-poc-01.cluster-[xxx].[region].rds.amazonaws.com -u admin -p

-- Create test database
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

-- Create test table
CREATE TABLE IF NOT EXISTS test_data (
    id INT PRIMARY KEY AUTO_INCREMENT,
    data VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert test data
INSERT INTO test_data (data) VALUES ('Test data 1'), ('Test data 2');

-- Generate slow query
SELECT SLEEP(3), COUNT(*) FROM test_data;

-- Generate error
SELECT * FROM non_existent_table;

-- More slow queries
SELECT BENCHMARK(1000000, MD5('test'));
SELECT * FROM test_data WHERE SLEEP(2);
```

### 7.2 Monitor Data Flow

1. **Check Discovery Service**:
```bash
aws logs tail /ecs/aurora-log-discovery --follow --filter-pattern "discovered"
```

2. **Check Kafka Topics**:
```bash
# From ECS instance with Kafka tools
bin/kafka-console-consumer.sh \
    --bootstrap-server [kafka-public-ip]:9092 \
    --topic aurora-logs-slowquery \
    --from-beginning \
    --max-messages 5
```

3. **Check Processor Service**:
```bash
aws logs tail /ecs/aurora-log-processor --follow --filter-pattern "processed"
```

4. **Verify S3 Files**:
```bash
aws s3 ls s3://company-aurora-logs-poc/slowquery/ --recursive
aws s3 ls s3://company-aurora-logs-poc/error/ --recursive
```

5. **Check OpenObserve**:
   - Go to **Logs** → Select `aurora-slowquery` stream
   - You should see parsed slow query logs
   - Check `aurora-error` stream for error logs

## Step 8: Monitoring and Validation

### 8.1 Service Health Dashboard

Create a CloudWatch dashboard:
1. **CloudWatch Console** → **Dashboards** → **Create dashboard**
2. Name: `aurora-logs-poc-dashboard`
3. Add widgets:
   - ECS Service CPU/Memory utilization
   - Task count per service
   - ALB target health
   - Kafka consumer lag (custom metric)

### 8.2 Verify All Components

```bash
# Check all services are running
aws ecs list-services --cluster aurora-logs-poc-cluster

# Check service status
for service in kafka-service openobserve-service discovery-service processor-service; do
  echo "=== $service ==="
  aws ecs describe-services \
    --cluster aurora-logs-poc-cluster \
    --services $service \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}'
done

# Check container insights
aws cloudwatch get-metric-statistics \
  --namespace ECS/ContainerInsights \
  --metric-name ServiceCount \
  --dimensions Name=ClusterName,Value=aurora-logs-poc-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

## Summary

Phase 4 accomplishes:

### Infrastructure:
- ECS cluster with auto-scaling EC2 instances (100 GiB EBS storage each)
- Service discovery namespace for internal communication
- Host volumes for persistent container storage

### Services Deployed:
- Kafka service with EBS-backed storage
- OpenObserve with EBS-backed storage and ALB integration
- Discovery service (1 instance)
- Processor service (2 instances with auto-scaling)

### Configuration Updates:
- **ARM64 runtime platform** explicitly set for all task definitions
- **Non-blocking log mode** with 25MB buffer for all services
- **EC2 launch type** for all services (no Fargate)

### Monitoring:
- CloudWatch Container Insights enabled
- Service health monitoring
- Complete data flow validation

The Aurora MySQL Log Processing POC is now fully deployed and operational with all requested optimizations!