# Aurora Log System - ECS Terraform Configuration

This Terraform configuration deploys the Aurora Log System using Amazon ECS (Elastic Container Service) with Fargate, providing a cost-effective alternative to EKS.

## Cost Comparison

| Service | EKS | ECS | Savings |
|---------|-----|-----|---------|
| Control Plane | $72/month | $0/month | $72/month |
| Worker Nodes | $24.43/month | N/A (Fargate) | - |
| Fargate Tasks | N/A | ~$20-30/month | - |
| **Total** | **$96.43/month** | **$20-30/month** | **~$66-76/month** |

## Architecture

- **ECS Cluster**: Managed container orchestration (no control plane costs)
- **Fargate**: Serverless compute for containers (pay only for running tasks)
- **Service Discovery**: AWS Cloud Map for internal DNS
- **Auto Scaling**: Application Auto Scaling for dynamic scaling
- **Load Balancer**: ALB for OpenObserve (production only)

## Services Deployed

1. **Discovery Service**
   - Discovers Aurora log files from RDS
   - Uses Valkey/Redis for caching RDS API calls
   - Publishes to Kafka

2. **Processor Service**
   - Consumes from Kafka
   - Downloads and processes log files
   - Sends to OpenObserve
   - Auto-scales based on CPU/Memory

3. **Kafka**
   - Message broker for log file queue
   - Single instance for POC

4. **OpenObserve**
   - Log storage and search
   - Web UI for querying logs

## Key Features

- **ARM64/Graviton**: All services run on ARM64 for cost savings
- **Fargate Spot**: Processor service uses Spot instances (70% discount)
- **Auto Scaling**: Automatic scaling based on load
- **Service Discovery**: Internal DNS via AWS Cloud Map
- **Scheduled Scaling**: Scale down at night for POC

## Prerequisites

- AWS CLI configured
- Terraform >= 1.0
- Existing infrastructure:
  - VPC and Subnets
  - RDS Aurora cluster
  - DynamoDB tables
  - S3 buckets
  - ECR repository with Docker images
  - Valkey/ElastiCache cluster

## Usage

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Review the plan:
   ```bash
   terraform plan -var-file=terraform.tfvars.poc
   ```

3. Apply the configuration:
   ```bash
   terraform apply -var-file=terraform.tfvars.poc
   ```

## Accessing Services

### POC Environment
- Use ECS Exec to access containers:
  ```bash
  aws ecs execute-command --cluster aurora-logs-poc-ecs-cluster \
    --task <task-id> \
    --container openobserve \
    --interactive \
    --command "/bin/sh"
  ```

### Production Environment
- OpenObserve available via ALB: `http://<alb-dns-name>`

## Environment Variables

All configuration is done through environment variables in task definitions:
- `AWS_REGION`: AWS region
- `S3_BUCKET`: Aurora logs bucket
- `KAFKA_BROKERS`: Kafka service endpoint
- `VALKEY_URL`: Redis cache endpoint
- `OPENOBSERVE_URL`: OpenObserve endpoint

## Cost Optimization

1. **Fargate Spot**: Processor service uses Spot for 70% savings
2. **Scheduled Scaling**: Scale to 0 at night in POC
3. **ARM64/Graviton**: 20% cheaper than x86
4. **No ALB in POC**: Saves ~$16/month

## Monitoring

- CloudWatch Container Insights (production only)
- CloudWatch Logs for all services
- Auto Scaling metrics

## Cleanup

To destroy all resources:
```bash
terraform destroy -var-file=terraform.tfvars.poc
```

Note: Valkey/ElastiCache has lifecycle protection and won't be destroyed.