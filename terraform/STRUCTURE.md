# ECS Terraform Structure

## Files Overview

### Core Infrastructure
- **main.tf**: Main configuration with ECS cluster, IAM roles, and data sources
- **variables.tf**: Input variables including ECS-specific settings
- **versions.tf**: Terraform and provider versions (copied from EKS)

### ECS Services
- **ecs-services.tf**: Task definitions and services for all containers
  - Discovery Service
  - Processor Service
  - Kafka
  - OpenObserve

### Networking & Discovery
- **service-discovery.tf**: AWS Cloud Map configuration for internal DNS
- **load-balancer.tf**: ALB configuration for OpenObserve (production only)

### Scaling & Operations
- **auto-scaling.tf**: Auto-scaling policies and scheduled scaling
- **secrets.tf**: Secrets Manager for OpenObserve credentials

### Configuration Files
- **terraform.tfvars.poc**: POC environment variables
- **terraform.tfvars.poc.example**: Example POC configuration
- **terraform.tfvars.production.example**: Example production configuration
- **backend.tf.example**: S3 backend configuration example

## Key Differences from EKS Version

1. **No Control Plane Cost**: ECS is free, saving $72/month
2. **Fargate Instead of EC2**: Serverless containers, pay per use
3. **Service Discovery**: AWS Cloud Map instead of Kubernetes DNS
4. **Auto Scaling**: AWS Application Auto Scaling instead of HPA
5. **Secrets**: AWS Secrets Manager instead of Kubernetes Secrets
6. **Load Balancer**: Optional ALB for production only

## Resource Naming Convention

All resources follow the pattern: `{name_prefix}-{resource_type}-{identifier}`

Examples:
- ECS Cluster: `aurora-logs-poc-ecs-cluster`
- Task Definition: `aurora-logs-poc-discovery`
- Service: `discovery` (within the cluster)
- Security Group: `aurora-logs-poc-ecs-tasks-sg`

## Cost Optimization Features

1. **Fargate Spot**: Processor service uses Spot instances (70% discount)
2. **ARM64/Graviton**: All tasks use ARM64 architecture
3. **Scheduled Scaling**: Scale down to 0 at night for POC
4. **No ALB in POC**: Direct access via ECS Exec
5. **Single Instance Services**: Kafka and OpenObserve run single instances

## Existing Resources Used

The configuration reuses these existing resources:
- VPC and Subnets
- RDS Aurora Cluster
- DynamoDB Tables (3)
- S3 Buckets (2)
- ECR Repository
- Valkey/ElastiCache Cluster
- Security Groups (RDS, Kafka, OpenObserve)
- IAM Roles (ecsTaskExecutionRole)