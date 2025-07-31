# Phase 4: Code Changes - ARM64 Runtime Platform & Non-blocking Logs

## Overview
This document highlights the specific changes made in Phase 4 for ARM64 runtime platform and non-blocking log configuration.

## 1. Runtime Platform Addition (All Task Definitions)

### Added to ALL task definitions:
```json
"runtimePlatform": {
  "operatingSystemFamily": "LINUX",
  "cpuArchitecture": "ARM64"
}
```

This was added to:
- Kafka Task Definition (Section 2.1)
- OpenObserve Task Definition (Section 2.2)
- Discovery Task Definition (Section 2.3)
- Processor Task Definition (Section 2.4)

**Before:**
```json
{
  "family": "kafka-task",
  "taskRoleArn": "...",
  "executionRoleArn": "...",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "2048",
  "memory": "4096",
  // runtime platform was missing
  "volumes": [...]
}
```

**After:**
```json
{
  "family": "kafka-task",
  "taskRoleArn": "...",
  "executionRoleArn": "...",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["EC2"],
  "cpu": "2048",
  "memory": "4096",
  "runtimePlatform": {
    "operatingSystemFamily": "LINUX",
    "cpuArchitecture": "ARM64"
  },
  "volumes": [...]
}
```

## 2. Non-blocking Log Mode Addition (All Services)

### Updated logConfiguration for ALL services:

**Before:**
```json
"logConfiguration": {
  "logDriver": "awslogs",
  "options": {
    "awslogs-group": "/ecs/apache-kafka",
    "awslogs-region": "[region]",
    "awslogs-stream-prefix": "ecs",
    "awslogs-create-group": "true"
  }
}
```

**After:**
```json
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
}
```

Key additions:
- `"mode": "non-blocking"` - Prevents container from blocking if logs can't be sent
- `"max-buffer-size": "25m"` - 25MB buffer for log messages

## 3. Kafka Topic Creation Update

### Section 5.2: Initialize Kafka Topics

**Updated Java version for Kafka 4.0:**
```bash
# Before:
sudo yum install -y java-11-amazon-corretto
wget https://downloads.apache.org/kafka/3.8.0/kafka_2.13-3.8.0.tgz

# After:
sudo yum install -y java-17-amazon-corretto
wget https://downloads.apache.org/kafka/4.0.0/kafka_2.13-4.0.0.tgz
```

## 4. Complete Task Definition Examples

### Kafka Task Definition (Complete Updated Version):
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

## 5. Summary of Changes by Service

### All Services (Kafka, OpenObserve, Discovery, Processor):
- ✅ Added `runtimePlatform` with `ARM64` architecture
- ✅ Added `"mode": "non-blocking"` to log configuration
- ✅ Added `"max-buffer-size": "25m"` to log options
- ✅ Already using EC2 launch type only (no changes needed)

### Service-Specific Log Groups:
- Kafka: `/ecs/apache-kafka`
- OpenObserve: `/ecs/openobserve`
- Discovery: `/ecs/aurora-log-discovery`
- Processor: `/ecs/aurora-log-processor`

## 6. Benefits of These Changes

### ARM64 Runtime Platform:
- Ensures tasks run on ARM64 architecture EC2 instances
- Matches the ARM64 container images built in Phase 3
- Better performance and cost efficiency on Graviton instances

### Non-blocking Log Mode:
- Prevents container failures due to logging issues
- Continues running even if CloudWatch Logs is temporarily unavailable
- 25MB buffer provides resilience for log delivery
- Default behavior changed in June 2025 to prioritize availability

## 7. Validation Commands

After deployment, verify the changes:

```bash
# Check task definition runtime platform
aws ecs describe-task-definition \
  --task-definition kafka-task:latest \
  --query 'taskDefinition.runtimePlatform'

# Expected output:
{
  "operatingSystemFamily": "LINUX",
  "cpuArchitecture": "ARM64"
}

# Check log configuration
aws ecs describe-task-definition \
  --task-definition kafka-task:latest \
  --query 'taskDefinition.containerDefinitions[0].logConfiguration'

# Expected output includes:
{
  "logDriver": "awslogs",
  "mode": "non-blocking",
  "options": {
    ...
    "max-buffer-size": "25m"
  }
}
```

## 8. Rollback Considerations

If issues arise with non-blocking logs:
1. Remove `"mode": "non-blocking"` from log configuration
2. Remove `"max-buffer-size"` option
3. Update task definition revision
4. Update service to use new revision

Note: ARM64 runtime platform should not need rollback as it matches our container architecture.