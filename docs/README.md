# Aurora Log System

A comprehensive, cost-optimized system for extracting, processing, and analyzing logs from 316 AWS Aurora RDS instances. This system processes approximately 100TB of logs monthly with built-in high availability, auto-scaling, and security features.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Goal & Problem Statement](#goal--problem-statement)
3. [Cost Optimization](#cost-optimization)
4. [Deployment Guide](#deployment-guide)
5. [Kubernetes Deployment Strategy](#kubernetes-deployment-strategy)
6. [Operations Guide](#operations-guide)
7. [Valkey Usage](#valkey-usage)
8. [Jenkins CI/CD](#jenkins-cicd)
9. [Terraform Infrastructure](#terraform-infrastructure)
10. [Implementation Status](#implementation-status)
11. [Files to Delete](#files-to-delete)

---

## Architecture Overview

### System Architecture

The Aurora Log System consists of five main components:

1. **Discovery Service**
   - Discovers Aurora instances and available log files via RDS API
   - Publishes log discovery messages to Kafka
   - Updates DynamoDB with instance metadata
   - Uses Valkey to cache RDS API responses (70-90% reduction)

2. **Processor Service**
   - Consumes messages from Kafka
   - Downloads log files from RDS
   - Processes and uploads to S3
   - Sends logs to OpenObserve for analysis
   - Updates DynamoDB with processing state

3. **Kafka**
   - Ensures FIFO message ordering
   - Provides durability and replay capability
   - Handles backpressure and scaling

4. **DynamoDB Tables**
   - `instance-metadata`: Stores RDS instance information (7-day TTL)
   - `tracking`: Tracks log file processing positions (no TTL)
   - `jobs`: Manages processing job state (30-day TTL)

5. **OpenObserve**
   - Provides log search and analytics
   - Real-time dashboards and alerting
   - Long-term log retention

### Data Flow

```
RDS Instances → Discovery Service → Kafka → Processor Service → S3 & OpenObserve
                       ↓                            ↓
                   DynamoDB                     DynamoDB
                       ↑                            ↑
                  Valkey Cache                      |
                  (RDS API only)              (State Updates)
```

### Key Design Decisions

1. **Kafka over SQS/DynamoDB**: 4-5x cheaper at scale, better FIFO guarantees
2. **ARM64/Graviton**: 20-40% better price/performance
3. **Fargate Spot**: 70% cost savings for processor workloads
4. **DynamoDB DAX**: 94% cheaper than ElastiCache for production

---

## Goal & Problem Statement

### Project Goal

Build a cost-effective, scalable system to:
- Extract logs from 316 Aurora RDS instances
- Process ~100TB of logs monthly
- Provide searchable log analytics
- Maintain < $150/month POC cost
- Scale to production with < $7,000/month

### The Challenge

**Problem**: AWS RDS API rate limits create bottlenecks when monitoring 316 instances
- API calls limited to 100-1000 requests/second
- Each instance requires multiple API calls
- Log files change every 5 minutes
- Direct polling would hit rate limits

**Solution**: 
- Valkey caches RDS API responses (70-90% reduction)
- Kafka provides buffering and FIFO ordering
- Horizontal scaling with sharding
- Exponential backoff with jitter

---

## Cost Optimization

### POC Environment: $89-150/month

| Component | Configuration | Cost |
|-----------|--------------|------|
| EKS Control | Standard | $73 |
| Compute | t4g.small free + t3.micro | $0-15 |
| RDS | t4g.micro (20% usage) | $40 |
| DynamoDB | Free tier | $0 |
| ElastiCache | None or t4g.micro | $0-12 |
| S3 | Free tier | $0 |

**Key Strategies**:
- Leverage AWS free tier (t4g.small until Dec 2025)
- Auto-shutdown on weekends
- NodePort instead of ALB
- Single instance deployments

### Production Environment: $4,500-7,000/month

| Component | Current | Optimized | Savings |
|-----------|---------|-----------|---------|
| EKS Control | $73 | $73 | - |
| Compute | $1,794-5,382 | $1,200-1,800 | 33-67% |
| DynamoDB | $1,200 | $400 | 67% |
| Cache | $6,998 | $392 (DAX) | 94% |
| S3 | $1,500 | $1,000 | 33% |

**Key Strategies**:
- Fargate Spot for processors (80% spot)
- DynamoDB DAX instead of ElastiCache
- S3 Intelligent Tiering
- Scheduled scaling (reduce 60% off-peak)
- 1-year Savings Plans (54% additional discount)

### With Commitments
- **Compute Savings Plan**: Additional 54% off Fargate
- **Reserved DAX**: Additional 40% off
- **Final Production Cost**: $3,000-4,500/month

---

## Deployment Guide

### Prerequisites

1. **AWS Account Setup**
   - AWS CLI configured
   - Sufficient IAM permissions
   - Service quotas verified

2. **Required Tools**
   - Terraform >= 1.5.0
   - kubectl >= 1.27
   - Helm >= 3.12
   - Docker >= 24.0
   - Go >= 1.21 (for local development)

### Step 1: Infrastructure Deployment

```bash
# Clone repository
git clone https://github.com/your-org/aurora-log-system
cd aurora-log-system

# Configure Terraform backend
cd terraform
cp backend.tf.example backend.tf
# Edit backend.tf with your S3 bucket

# Deploy infrastructure
terraform init
terraform workspace new poc  # or production
terraform plan -var-file=terraform.tfvars.poc.example
terraform apply -var-file=terraform.tfvars.poc.example
```

### Step 2: Build and Push Images

```bash
# Set environment variables
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
export ECR_REGISTRY=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# Build and push images
docker buildx create --name aurora-builder --use
docker buildx build --platform linux/arm64 \
  -t $ECR_REGISTRY/aurora-log-system:discovery-latest \
  -f Dockerfile.discovery --push .

docker buildx build --platform linux/arm64 \
  -t $ECR_REGISTRY/aurora-log-system:processor-latest \
  -f Dockerfile.processor --push .
```

### Step 3: Deploy to Kubernetes

```bash
# Update kubeconfig
aws eks update-kubeconfig --name aurora-logs-poc --region $AWS_REGION

# Create namespace
kubectl create namespace aurora-logs

# Deploy secrets
kubectl create secret generic openobserve-credentials \
  --from-literal=admin-email=admin@company.com \
  --from-literal=admin-password=$(openssl rand -base64 32) \
  -n aurora-logs

# Deploy using values
cd k8s
cp values-poc.yaml values.yaml
# Edit values.yaml with your configuration
./apply-with-values.sh
```

### Step 4: Verify Deployment

```bash
# Check pod status
kubectl get pods -n aurora-logs

# Check logs
kubectl logs -f deployment/discovery -n aurora-logs
kubectl logs -f deployment/processor -n aurora-logs

# Access OpenObserve
kubectl port-forward service/openobserve-service 5080:5080 -n aurora-logs
# Open http://localhost:5080
```

---

## Kubernetes Deployment Strategy

### Overview

This document outlines the Kubernetes deployment strategy for the Aurora Log System after infrastructure is provisioned with Terraform.

### Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        EKS Cluster                          │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │  Discovery  │  │  Processor  │  │    Kafka    │       │
│  │ Deployment  │  │ Deployment  │  │ StatefulSet │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │OpenObserve  │  │  ConfigMaps │  │   Secrets   │       │
│  │ Deployment  │  │  & Values   │  │ Credentials │       │
│  └─────────────┘  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Deployment Methods

#### 1. Helm Charts (Recommended)

**Advantages:**
- Template reusability
- Easy configuration management
- Built-in rollback support
- Dependency management

**Structure:**
```
helm/
├── aurora-log-system/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-poc.yaml
│   ├── values-production.yaml
│   └── templates/
│       ├── discovery-deployment.yaml
│       ├── processor-deployment.yaml
│       ├── kafka-statefulset.yaml
│       └── ...
```

**Deployment:**
```bash
# Install
helm install aurora-logs ./helm/aurora-log-system \
  -f ./helm/aurora-log-system/values-poc.yaml \
  -n aurora-logs

# Upgrade
helm upgrade aurora-logs ./helm/aurora-log-system \
  -f ./helm/aurora-log-system/values-production.yaml \
  -n aurora-logs
```

#### 2. Kustomize (Alternative)

**Structure:**
```
k8s/
├── base/
│   ├── kustomization.yaml
│   └── deployments/
├── overlays/
│   ├── poc/
│   │   └── kustomization.yaml
│   └── production/
│       └── kustomization.yaml
```

### Key Considerations

1. **GitOps Integration**
   - Use ArgoCD or Flux for automated deployments
   - Separate repository for Kubernetes manifests
   - Environment-specific branches/folders

2. **Security**
   - RBAC policies per service
   - Pod Security Standards
   - Network policies for isolation
   - Secrets management with AWS Secrets Manager

3. **Scaling Strategy**
   - HPA for automatic scaling
   - KEDA for advanced metrics
   - Cluster Autoscaler/Karpenter

4. **Multi-Environment**
   - Namespace separation
   - Resource quotas
   - Different node pools

### POC vs Production Configurations

| Aspect | POC | Production |
|--------|-----|------------|
| **Replicas** | 1 each | 3+ with auto-scaling |
| **Resources** | Minimal | Production-grade |
| **Storage** | 10-20GB | 1TB+ with lifecycle |
| **Networking** | NodePort | ALB with TLS |
| **Monitoring** | Basic | Full observability |
| **Availability** | Single AZ | Multi-AZ HA |

### Post-Deployment Tasks

1. **Configure Monitoring**
   ```bash
   # Deploy Prometheus/Grafana
   helm install prometheus prometheus-community/kube-prometheus-stack
   ```

2. **Setup Log Aggregation**
   ```bash
   # Configure Fluent Bit
   kubectl apply -f k8s/daemonsets/fluent-bit-daemonset.yaml
   ```

3. **Enable Autoscaling**
   ```bash
   # Apply HPA
   kubectl apply -f k8s/hpa/autoscaling.yaml
   ```

4. **Configure Backup**
   - Enable automated EBS snapshots
   - Configure DynamoDB backups
   - S3 cross-region replication

---

## Operations Guide

### Daily Operations

#### Health Checks

```bash
# Check system health
kubectl get pods -n aurora-logs
kubectl top pods -n aurora-logs

# Check processing metrics
kubectl exec -it deployment/discovery -n aurora-logs -- ./discovery -stats

# Monitor Kafka lag
kubectl exec -it kafka-0 -n aurora-logs -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group aurora-processor-group --describe
```

#### Log Analysis

```bash
# View discovery logs
kubectl logs -f deployment/discovery -n aurora-logs | grep ERROR

# View processor logs with timestamps
kubectl logs -f deployment/processor -n aurora-logs --timestamps

# Search OpenObserve
curl -X POST http://openobserve-service:5080/api/search \
  -H "Content-Type: application/json" \
  -d '{"query": "error_type:timeout", "from": "now-1h"}'
```

### Troubleshooting

#### Common Issues

1. **RDS API Rate Limits**
   ```bash
   # Check cache hit rate
   kubectl exec -it deployment/discovery -n aurora-logs -- \
     redis-cli --stat
   
   # Increase discovery interval
   kubectl set env deployment/discovery \
     DISCOVERY_INTERVAL_MIN=10 -n aurora-logs
   ```

2. **Kafka Consumer Lag**
   ```bash
   # Scale up processors
   kubectl scale deployment processor --replicas=10 -n aurora-logs
   
   # Check consumer group
   kubectl exec -it kafka-0 -n aurora-logs -- \
     kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
     --group aurora-processor-group --reset-offsets \
     --to-earliest --execute
   ```

3. **DynamoDB Throttling**
   ```bash
   # Check metrics
   aws cloudwatch get-metric-statistics \
     --namespace AWS/DynamoDB \
     --metric-name ConsumedReadCapacityUnits \
     --dimensions Name=TableName,Value=aurora-log-file-tracking \
     --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 300 --statistics Average
   ```

### Maintenance Tasks

#### Weekly
- Review cost reports
- Check S3 lifecycle transitions
- Validate backup integrity
- Update pod resource requests based on usage

#### Monthly
- Security patches and updates
- Performance tuning
- Capacity planning review
- Disaster recovery drill

### Scaling Operations

#### Manual Scaling
```bash
# Scale discovery for more shards
kubectl scale deployment discovery --replicas=5 -n aurora-logs

# Scale processors for higher throughput
kubectl scale deployment processor --replicas=20 -n aurora-logs
```

#### Auto-scaling Configuration
```yaml
# HPA for processor
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: processor-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: processor
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
```

### Monitoring & Alerting

#### Key Metrics
- **Discovery**: API calls/min, cache hit rate, instances discovered
- **Processor**: Messages processed/sec, S3 upload latency, error rate
- **Kafka**: Consumer lag, partition distribution, disk usage
- **DynamoDB**: Consumed capacity, throttled requests, item count

#### Alert Thresholds
- RDS API errors > 10/min
- Kafka consumer lag > 1000 messages
- Processor error rate > 5%
- DynamoDB throttling > 0
- S3 upload failures > 1%

### Backup & Recovery

#### Backup Strategy
1. **DynamoDB**: Point-in-time recovery enabled
2. **S3**: Cross-region replication for critical logs
3. **Kafka**: Topic replication factor of 3
4. **Configuration**: GitOps with version control

#### Recovery Procedures
```bash
# Restore DynamoDB table
aws dynamodb restore-table-to-point-in-time \
  --source-table-name aurora-log-file-tracking \
  --target-table-name aurora-log-file-tracking-restored \
  --restore-date-time "2024-01-15T00:00:00Z"

# Replay Kafka messages
kubectl exec -it kafka-0 -n aurora-logs -- \
  kafka-consumer-groups.sh --bootstrap-server localhost:9092 \
  --group aurora-processor-group-replay \
  --reset-offsets --to-datetime "2024-01-15T00:00:00.000" \
  --execute
```

---

## Valkey Usage

### Architecture Principle

**IMPORTANT**: Valkey/Redis is used EXCLUSIVELY for caching RDS API responses to reduce API rate limits. It is NOT used for any state management or application data caching.

### Current Implementation

#### Discovery Service (✅ Uses Valkey)
The Discovery service uses Valkey to cache RDS API responses:

1. **DescribeDBClusters** - Cached for 5 minutes
2. **DescribeDBInstances** - Cached for 5 minutes  
3. **DescribeDBLogFiles** - Cached for 1 minute

This reduces RDS API calls by 70-90% when discovering logs across 316 RDS instances.

#### Processor Service (❌ Does NOT use Valkey)
The Processor service does NOT use Valkey because:
- It downloads log file content (not metadata)
- Log content changes constantly and should not be cached
- Each DownloadDBLogFilePortion call gets unique data

### State Management

All state management is handled by DynamoDB tables:
- **instance-metadata**: Stores RDS instance information
- **tracking**: Tracks log file processing positions
- **jobs**: Manages processing job state

### Configuration

#### Environment Variables
- `VALKEY_URL`: Only used by Discovery service
- Format: `redis://aurora-log-cache-poc.[cache-id].ng.0001.[region].cache.amazonaws.com:6379`

#### Kubernetes ConfigMap
```yaml
VALKEY_URL: "redis://..."  # Used by Discovery service only for RDS API caching
```

### Cost Optimization

- POC: Single cache.t4g.micro instance ($12/month) or none
- Production: DynamoDB DAX instead of ElastiCache ($392/month vs $6,998/month)

### Key Points

1. ✅ Valkey caches ONLY RDS API responses
2. ❌ Valkey does NOT cache application state
3. ❌ Valkey does NOT cache log content
4. ✅ All state is managed in DynamoDB
5. ✅ Processor service doesn't need Valkey access

---

## Jenkins CI/CD

### Jenkins Setup Requirements

1. **For Public Repositories:**
   ```groovy
   // Update Jenkinsfile line 87:
   url: 'https://github.com/YOUR_USERNAME/YOUR_REPO.git'
   ```

2. **For Private Repositories:**
   - Add GitHub credentials in Jenkins:
     - Go to Jenkins → Manage Jenkins → Credentials
     - Add Username with password (use GitHub Personal Access Token)
     - ID: `github-credentials`
   
   - Update Jenkinsfile:
   ```groovy
   git branch: "${env.BRANCH_NAME ?: 'main'}", 
       url: 'https://github.com/YOUR_USERNAME/YOUR_REPO.git',
       credentialsId: 'github-credentials'
   ```

3. **For Local Development:**
   - The current Jenkinsfile checks if code exists in workspace
   - Jenkins will use existing checkout if available

### Running Jenkins Pipeline

### Jenkins Shared Library

This shared library provides reusable functions for the Aurora Log System CI/CD pipeline.

#### Library Structure

```
jenkins/
├── vars/
│   ├── buildGo.groovy
│   ├── buildDocker.groovy
│   ├── pushToECR.groovy
│   └── runTests.groovy
└── src/
    └── com/
        └── auroralogs/
            └── Utils.groovy
```

#### Key Features

1. **ARM64 Support**: All builds target ARM64/Graviton architecture
2. **Security Scanning**: Comprehensive scanning with Trivy, Grype, Snyk, Cosign, and Docker Scout
3. **Multi-stage Builds**: Optimized Docker images with minimal attack surface
4. **Parallel Execution**: Security scans run in parallel for faster feedback

#### Usage in Jenkinsfile

```groovy
@Library('aurora-log-system') _

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: golang
    image: golang:1.21
    command: ['sleep', '99999']
"""
        }
    }
    
    stages {
        stage('Build') {
            steps {
                buildGo(service: 'discovery')
            }
        }
        
        stage('Docker Build') {
            steps {
                buildDocker(
                    service: 'discovery',
                    dockerfile: 'Dockerfile.discovery',
                    platform: 'linux/arm64'
                )
            }
        }
        
        stage('Push to ECR') {
            steps {
                pushToECR(
                    service: 'discovery',
                    region: 'us-east-1',
                    accountId: '123456789012'
                )
            }
        }
    }
}
```

#### Security Scanning Stage

The pipeline includes comprehensive security scanning:

```groovy
stage('Security Scan - Comprehensive') {
    parallel {
        stage('Trivy Scan') {
            steps {
                sh '''
                    trivy image --severity HIGH,CRITICAL \
                      --format json \
                      --output trivy-report.json \
                      ${ECR_REGISTRY}/aurora-log-system:${SERVICE}-${BUILD_NUMBER}
                '''
            }
        }
        stage('Grype Scan') {
            steps {
                sh '''
                    grype ${ECR_REGISTRY}/aurora-log-system:${SERVICE}-${BUILD_NUMBER} \
                      -o json > grype-report.json
                '''
            }
        }
        stage('Snyk Scan') {
            steps {
                sh '''
                    snyk container test \
                      ${ECR_REGISTRY}/aurora-log-system:${SERVICE}-${BUILD_NUMBER} \
                      --json-file-output=snyk-report.json || true
                '''
            }
        }
    }
}
```

---

## Terraform Infrastructure

### Terraform Module Structure

The Terraform configuration is organized into reusable modules for better maintainability and consistency.

#### Directory Structure

```
terraform/
├── main.tf                 # Root module configuration
├── variables.tf           # Input variables
├── outputs.tf            # Output values
├── versions.tf           # Provider versions (AWS 6.5.0)
├── backend.tf.example    # S3 backend configuration template
├── terraform.tfvars.poc.example      # POC environment values
├── terraform.tfvars.production.example # Production environment values
└── modules/
    ├── vpc/              # VPC with public/private/database subnets
    ├── iam/              # IAM roles and policies
    ├── dynamodb/         # DynamoDB tables with TTL
    ├── s3/               # S3 buckets with lifecycle policies
    ├── rds/              # Aurora MySQL cluster
    ├── elasticache/      # Valkey cache cluster
    ├── eks/              # EKS cluster with node groups
    └── ecr/              # ECR repositories
```

#### Key Features

1. **Multi-Environment Support**
   - Terraform workspaces for poc/production
   - Environment-specific tfvars files
   - Consistent tagging strategy

2. **Cost Optimization**
   - ARM64/Graviton instances by default
   - Spot instance support
   - Lifecycle policies for S3
   - Auto-scaling configurations

3. **Security**
   - Least privilege IAM policies
   - Encryption at rest for all services
   - Private subnets for databases
   - Security group isolation

4. **High Availability**
   - Multi-AZ deployments
   - Auto-scaling groups
   - Cross-AZ replication

#### Usage

```bash
# Initialize Terraform
terraform init

# Create workspace
terraform workspace new poc

# Plan deployment
terraform plan -var-file=terraform.tfvars.poc.example

# Apply configuration
terraform apply -var-file=terraform.tfvars.poc.example

# Destroy resources
terraform destroy -var-file=terraform.tfvars.poc.example
```

#### Module Examples

**VPC Module:**
```hcl
module "vpc" {
  source = "./modules/vpc"
  
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  az_count    = var.az_count
  
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
}
```

**EKS Module:**
```hcl
module "eks" {
  source = "./modules/eks"
  
  cluster_name     = "${var.name_prefix}-${var.environment}"
  cluster_version  = "1.29"
  instance_types   = ["t4g.medium", "t4g.large"]
  
  min_size     = var.environment == "poc" ? 1 : 3
  max_size     = var.environment == "poc" ? 3 : 20
  desired_size = var.environment == "poc" ? 1 : 3
}
```

### AWS Provider 6.5.0 Update

The Terraform configuration uses AWS Provider version 6.5.0 (latest as of January 2025) for:
- Better ARM64/Graviton instance support
- Enhanced EKS module functionality
- Improved DynamoDB TTL handling
- Better ElastiCache configuration options
- Enhanced S3 lifecycle policy support

---

## Implementation Status

### Phase Completion Summary

| Phase | Status | Key Deliverables |
|-------|--------|------------------|
| **Phase 1: AWS Foundation** | ✅ Complete | VPC, IAM roles, Security groups |
| **Phase 2: Database Infrastructure** | ✅ Complete | RDS, DynamoDB, ElastiCache, ECR |
| **Phase 3: Container Development** | ✅ Complete | Discovery/Processor services, Tests |
| **Phase 4: EKS Deployment** | ✅ Complete | K8s manifests, HPA, Monitoring |

### Current Implementation Details

#### AWS Foundation (Phase 1)
- ✅ VPC with public subnets configured
- ✅ EKS Node Group IAM role with all required permissions
- ✅ Security groups: `eks-node-sg`, `eks-control-plane-sg`, `kafka-pod-sg`, `valkey-cluster-sg`

#### Database Infrastructure (Phase 2)
- ✅ DynamoDB tables with TTL enabled
- ✅ ECR repositories for container images
- ✅ Placeholder values for RDS and ElastiCache endpoints

#### Application Development (Phase 3)
- ✅ Discovery service with sharding and RDS API caching
- ✅ Processor service with S3/OpenObserve integration
- ✅ Common packages for DynamoDB and metrics
- ✅ Comprehensive unit and integration tests
- ✅ Jenkins CI/CD pipeline with security scanning

#### Kubernetes Deployment (Phase 4)
- ✅ All services deployed with proper configurations
- ✅ HPA for auto-scaling
- ✅ Pod Security Standards implemented
- ✅ Fluent Bit for log aggregation
- ✅ Cost-optimized configurations

### Recent Updates

1. **Valkey Usage Clarification**
   - Valkey now ONLY caches RDS API responses
   - Removed improper instance detail caching
   - Processor service doesn't use Valkey

2. **Security Enhancements**
   - Removed Falco, Trivy runtime, OPA Gatekeeper
   - Implemented Pod Security Standards
   - Added comprehensive CI/CD security scanning

3. **Cost Optimization**
   - POC reduced to $89-150/month
   - Production optimized to $4,500-7,000/month
   - Fargate Spot and scheduled scaling

4. **Terraform Updates**
   - AWS Provider updated to 6.5.0
   - Complete infrastructure as code
   - Multi-environment support

---

## Files to Delete

### Files to Delete from Aurora Log System Codebase

This section lists all unnecessary files that should be removed from the codebase to keep it clean and maintainable.

#### 1. Build Failure Logs and Temporary Files
- `Jenkins.fail` - Contains old Jenkins build failure logs (1000+ lines)
- `JENKINS_FIX.md` - Temporary documentation for fixing Jenkins Go installation issues

**Reason**: These are debugging/troubleshooting files that are no longer needed.

#### 2. Duplicate Jenkins Pipeline Files
- `Jenkinsfile.docker` - Duplicate Jenkins pipeline with Docker agent
- `Jenkinsfile.docker-agent` - Another duplicate Jenkins pipeline variant

**Reason**: We already have `Jenkinsfile` (main) and `Jenkinsfile.simple` (simplified version). Multiple variants create confusion.

#### 3. Example/Sample Files (Keep as Documentation)
These files should be KEPT as they serve as templates:
- ✅ `terraform/backend.tf.example`
- ✅ `terraform/terraform.tfvars.poc.example`
- ✅ `terraform/terraform.tfvars.production.example`
- ✅ `k8s/values-example.yaml`

#### 4. Empty Directories
- `security/` - Empty directory (security manifests were removed)
- `terraform/environments/poc/` - Empty directory
- `terraform/environments/production/` - Empty directory

**Reason**: Empty directories serve no purpose. Environment-specific configs are handled via tfvars files.

#### 5. Potentially Redundant Documentation
Consider consolidating:
- `project-phases/costs.md` - Redundant with `cost-optimization.md`
- `PACKAGE-VERSIONS.md` - Package versions are already in go.mod and Dockerfiles

**Reason**: Duplicate information leads to inconsistencies.

#### 6. Git-specific Files (DO NOT DELETE)
These are essential Git files:
- ✅ `.git/` directory and all contents
- ✅ `.gitignore`

### Summary of Files to Delete

```bash
# Run these commands from the repository root to clean up:

# Remove build failure logs and fixes
rm -f Jenkins.fail
rm -f JENKINS_FIX.md

# Remove duplicate Jenkins pipelines
rm -f Jenkinsfile.docker
rm -f Jenkinsfile.docker-agent

# Remove empty directories
rmdir security/
rmdir terraform/environments/poc/
rmdir terraform/environments/production/
rmdir terraform/environments/

# Optional: Remove redundant documentation (review first)
# rm -f project-phases/costs.md
# rm -f PACKAGE-VERSIONS.md
```

### Files to Keep

#### Essential Documentation
- ✅ `README.md` - Main project documentation (this file)
- ✅ `CLAUDE.md` - Development guidance
- ✅ `project-phases/*.md` - Phase documentation

#### Configuration Examples
- ✅ All `.example` files - Serve as templates

Total files to delete: 4-6 files
Total space saved: ~50KB (mostly from Jenkins.fail)

---

## Quick Start

### POC Deployment (Under 30 minutes)

```bash
# 1. Deploy infrastructure
cd terraform
terraform init
terraform apply -var-file=terraform.tfvars.poc.example

# 2. Build and push images
./scripts/build-and-push.sh poc

# 3. Deploy to Kubernetes
cd k8s
kubectl create namespace aurora-logs
./apply-with-values.sh values-poc.yaml

# 4. Verify
kubectl get pods -n aurora-logs
```

### Production Deployment

```bash
# 1. Review configurations
cd terraform
cp terraform.tfvars.production.example terraform.tfvars.production
# Edit with your values

# 2. Deploy infrastructure
terraform workspace new production
terraform apply -var-file=terraform.tfvars.production

# 3. Deploy applications
cd k8s
./apply-with-values.sh values-production.yaml

# 4. Enable monitoring
kubectl apply -f monitoring/
```

---

## Support & Maintenance

### Getting Help

1. Check the [Operations Guide](#operations-guide) for troubleshooting
2. Review CloudWatch logs for detailed error messages
3. Use `kubectl describe` for Kubernetes issues
4. Check AWS service limits and quotas

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### License

This project is licensed under the MIT License - see the LICENSE file for details.