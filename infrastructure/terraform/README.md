# Aurora Log System - Terraform Deployment

This directory contains Terraform configuration for deploying the Aurora Log System to AWS EKS.

## Overview

The Terraform configuration deploys:
- Kubernetes namespace and RBAC
- Application services (Discovery, Processor, Kafka, OpenObserve, Valkey)
- Fluent Bit for K8s log collection
- Autoscaling with scale-to-zero capability
- Network policies for security
- Pod disruption budgets and resource quotas
- Monitoring and observability components

## Prerequisites

1. **AWS Resources** (must already exist):
   - EKS cluster: `aurora-logs-poc-cluster`
   - VPC and subnets
   - S3 bucket: `company-aurora-logs-poc`
   - DynamoDB tables: `aurora-instance-metadata`, `aurora-log-file-tracking`, `aurora-log-processing-jobs`
   - ECR repository: `aurora-log-system`
   - RDS Aurora cluster: `aurora-mysql-poc-01`

2. **Tools Required**:
   - Terraform >= 1.0
   - AWS CLI configured with appropriate credentials
   - kubectl
   - Docker (for building images)

3. **Container Images**:
   Build and push the required images before deployment:
   ```bash
   # Build images
   cd ../../discovery && docker build -t aurora-discovery:latest .
   cd ../processor && docker build -t aurora-processor:latest .
   cd ../kafka && docker build -t aurora-kafka:latest .
   
   # Tag and push to ECR (replace with your ECR URL)
   docker tag aurora-discovery:latest <ECR_URL>/aurora-log-system:discovery-latest
   docker push <ECR_URL>/aurora-log-system:discovery-latest
   # Repeat for processor and kafka images
   ```

## Quick Start

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Copy and configure variables**:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

3. **Review the plan**:
   ```bash
   terraform plan
   ```

4. **Apply the configuration**:
   ```bash
   terraform apply
   ```

5. **Configure kubectl**:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name aurora-logs-poc-cluster
   ```

6. **Verify deployment**:
   ```bash
   kubectl get pods -n aurora-logs
   kubectl get svc -n aurora-logs
   ```

## Configuration Options

### Cost Optimization

Enable aggressive cost optimization (recommended for POC):
```hcl
enable_cost_optimization = true  # Reduces resources by ~73%
enable_fargate          = false # Set to true for serverless pods
```

### High Availability

For production environments:
```hcl
enable_cost_optimization = false
kafka_replicas          = 3
openobserve_replicas    = 2
discovery_replicas      = 2
```

### Monitoring

Enable monitoring features:
```hcl
enable_monitoring    = true
enable_prometheus    = true  # If Prometheus is installed
enable_otel         = true   # For distributed tracing
enable_grafana_agent = true  # If using Grafana Cloud
```

### Autoscaling

Advanced autoscaling options:
```hcl
enable_vpa  = true  # Vertical Pod Autoscaler
enable_keda = true  # KEDA for Kafka-based scaling
```

## File Structure

```
.
├── main.tf                 # Main configuration, data sources
├── providers.tf            # Provider configurations
├── variables.tf            # Variable definitions
├── outputs.tf              # Output values
├── terraform.tfvars.example # Example variables file
├── k8s-deployment.tf       # Base K8s resources (namespace, RBAC, secrets, configmaps, PVCs)
├── k8s-services.tf         # Service deployments (Valkey, Kafka, OpenObserve, Discovery)
├── k8s-processor.tf        # Processor master-slave architecture
├── k8s-fluentbit.tf        # Fluent Bit configuration
├── k8s-autoscaling.tf      # HPA, VPA, and scaling policies
├── k8s-network-policies.tf # Network security policies
├── k8s-policies.tf         # PodDisruptionBudgets and ResourceQuotas
├── k8s-monitoring.tf       # Monitoring and observability
└── modules/                # Terraform modules
    ├── elasticache/        # Valkey cache cluster
    └── ...
```

## Accessing Services

### OpenObserve UI
```bash
kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080
# Access at http://localhost:5080
# Default credentials: admin@example.com / Complexpass#123
```

### View Logs
```bash
# Discovery logs
kubectl logs -n aurora-logs -l app=discovery --tail=100

# Processor logs
kubectl logs -n aurora-logs -l app=processor --tail=100

# Kafka logs
kubectl logs -n aurora-logs -l app=kafka --tail=100
```

### Monitor Autoscaling
```bash
# Check HPA status
kubectl get hpa -n aurora-logs

# Watch processor scaling
kubectl get pods -n aurora-logs -l app=processor -w
```

## Troubleshooting

### Common Issues

1. **Pods not starting**:
   ```bash
   kubectl describe pod <pod-name> -n aurora-logs
   kubectl logs <pod-name> -n aurora-logs
   ```

2. **Image pull errors**:
   - Ensure images are built and pushed to ECR
   - Check ECR permissions for the EKS node role

3. **Service account issues**:
   - Verify IAM roles exist and have correct trust policies
   - Check service account annotations

4. **Storage issues**:
   - Ensure gp3 storage class exists
   - Check PVC status: `kubectl get pvc -n aurora-logs`

### Debug Commands

```bash
# Check all resources
kubectl get all -n aurora-logs

# Check events
kubectl get events -n aurora-logs --sort-by='.lastTimestamp'

# Check service endpoints
kubectl get endpoints -n aurora-logs

# Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -n aurora-logs -- sh
```

## Cost Optimization Details

With `enable_cost_optimization = true`:
- Processor slaves scale to zero when idle
- Resource requests/limits reduced by 50-70%
- Single Kafka node instead of cluster
- Minimal resource allocations
- Estimated cost: ~$60-80/month (vs $305/month without optimization)

## Production Recommendations

1. **Security**:
   - Enable network policies
   - Use private ECR repositories
   - Implement pod security policies
   - Rotate credentials regularly

2. **Reliability**:
   - Enable PodDisruptionBudgets
   - Configure proper health checks
   - Implement proper backup strategies
   - Use multi-AZ deployments

3. **Performance**:
   - Tune resource limits based on actual usage
   - Configure appropriate autoscaling thresholds
   - Monitor Kafka lag and adjust partitions
   - Optimize batch sizes

4. **Monitoring**:
   - Enable Prometheus metrics
   - Configure alerts for critical conditions
   - Set up distributed tracing with OTEL
   - Monitor costs with AWS Cost Explorer

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Note**: This will only destroy resources created by Terraform. Pre-existing AWS resources (EKS cluster, VPC, etc.) will not be affected.