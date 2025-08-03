# Aurora Log System - Kubernetes Deployment

This directory contains all the Kubernetes manifests and scripts needed to deploy the Aurora Log System with a single command.

## Architecture Overview

The Aurora Log System consists of:
- **Discovery Service**: Discovers Aurora instances and monitors log files
- **Processor Service**: Downloads and processes log files, sends to OpenObserve
- **Kafka**: Message broker for log file events (KRaft mode, no ZooKeeper)
- **OpenObserve**: Log analytics platform with S3 backend
- **Valkey**: Redis-compatible cache for distributed operations

## Prerequisites

1. **EKS Cluster** with:
   - EKS Pod Identity enabled
   - OIDC provider configured
   - Nodes with sufficient resources (minimum 8GB RAM, 4 vCPUs)

2. **AWS Resources**:
   - DynamoDB tables: `aurora-log-tracking`, `aurora-instance-metadata`
   - S3 bucket: `company-aurora-logs-poc`
   - Existing ALB: `openobserve-alb` (optional)

3. **Tools Required**:
   - kubectl configured for your EKS cluster
   - AWS CLI v2 with appropriate credentials
   - jq for JSON processing

## Quick Start - One-Click Deployment

```bash
# 1. Set up IAM roles (only needed once per cluster)
./setup-iam.sh

# 2. Deploy everything
./deploy-all.sh
```

That's it! The system will be fully deployed and configured.

## Deployment Scripts

### setup-iam.sh
Creates IAM roles with EKS Pod Identity for secure AWS access:
- `AuroraLogDiscoveryRole` - For RDS and DynamoDB access
- `AuroraLogProcessorRole` - For RDS log downloads and DynamoDB
- `AuroraLogOpenObserveRole` - For S3 storage access

### deploy-all.sh
Main deployment script that:
1. Creates namespace and RBAC resources
2. Deploys ConfigMaps and Secrets
3. Creates Persistent Volume Claims
4. Deploys all services (Kafka, Valkey, OpenObserve)
5. Deploys Discovery and Processor services
6. Configures autoscaling (HPA)
7. Sets up network policies
8. Configures OpenObserve ALB integration

### health-check.sh
Validates the deployment:
```bash
./health-check.sh
```

Checks:
- All pods are running
- Services have endpoints
- Kafka topics exist
- No errors in logs
- AWS connectivity
- OpenObserve accessibility

### cleanup-all.sh
Removes everything:
```bash
./cleanup-all.sh
```

## Kubernetes Manifests

| File | Description |
|------|-------------|
| `01-namespace-rbac.yaml` | Namespace and service accounts with IAM annotations |
| `02-configmaps.yaml` | Application configuration |
| `02-secrets.yaml` | Credentials and secrets |
| `03-pvcs.yaml` | Persistent volume claims for Kafka and OpenObserve |
| `04-valkey.yaml` | Valkey (Redis) deployment |
| `04-deployments.yaml` | Main service deployments |
| `05-autoscaling.yaml` | Horizontal Pod Autoscalers |
| `06-network-policies.yaml` | Pod-to-pod communication rules |

## Configuration

### Resource Limits
Services are configured with conservative resource limits:
- Discovery: 256Mi-512Mi RAM, 100m-250m CPU
- Processor: 512Mi-1Gi RAM, 200m-500m CPU
- Kafka: 2Gi-4Gi RAM, 500m-1000m CPU
- OpenObserve: 4Gi-8Gi RAM, 1000m-2000m CPU

### Autoscaling
HPAs configured to:
- Start with 1 replica (minimal resources)
- Scale up when CPU > 80% or Memory > 85%
- Conservative scaling policies to prevent flapping

### Environment Variables
Key configurations in `02-configmaps.yaml`:
- `DISCOVERY_INTERVAL_MIN`: How often to scan for new logs (default: 5 min)
- `MAX_CONCURRENCY`: Parallel processing limit (default: 5)
- `BATCH_SIZE`: Log batch size for OpenObserve (default: 1000)

## Access Information

### OpenObserve UI
After deployment, access OpenObserve at:
- URL: `http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com/`
- Username: `admin@example.com`
- Password: `Complexpass#123`

### Port Forwarding (if ALB not available)
```bash
kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080
```

## Monitoring

### View Logs
```bash
# Discovery service logs
kubectl logs -f deployment/discovery -n aurora-logs

# Processor service logs
kubectl logs -f deployment/processor -n aurora-logs
```

### Check Metrics
```bash
# Pod resource usage
kubectl top pods -n aurora-logs

# HPA status
kubectl get hpa -n aurora-logs
```

## Troubleshooting

### Common Issues

1. **502 Bad Gateway for OpenObserve**
   - ALB target group has wrong IP
   - Run: `./deploy-all.sh` to re-register

2. **DynamoDB Permission Errors**
   - IAM roles not configured
   - Run: `./setup-iam.sh`

3. **Pods Stuck in Pending**
   - Check node resources: `kubectl describe nodes`
   - Check events: `kubectl get events -n aurora-logs`

4. **Kafka Connection Errors**
   - Ensure Kafka is ready before starting services
   - Check DNS resolution: `kubectl exec -it deployment/processor -n aurora-logs -- nslookup kafka-service`

### Debug Commands
```bash
# Describe problematic pod
kubectl describe pod <pod-name> -n aurora-logs

# Check service endpoints
kubectl get endpoints -n aurora-logs

# Verify secrets
kubectl get secrets -n aurora-logs

# Check PVC status
kubectl get pvc -n aurora-logs
```

## Production Considerations

1. **High Availability**
   - Increase Kafka replicas and replication factor
   - Deploy across multiple availability zones
   - Use dedicated node groups

2. **Security**
   - Enable network policies (already included)
   - Use private ALB for OpenObserve
   - Implement pod security policies

3. **Monitoring**
   - Export metrics to Prometheus
   - Set up alerts for failed health checks
   - Monitor DynamoDB and S3 costs

4. **Backup**
   - Regular snapshots of OpenObserve data
   - DynamoDB point-in-time recovery
   - Kafka log retention policies

## Maintenance

### Update Images
```bash
# Update deployment with new image
kubectl set image deployment/discovery discovery=072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:discovery-v2 -n aurora-logs
kubectl set image deployment/processor processor=072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:processor-v2 -n aurora-logs
```

### Scale Services
```bash
# Manual scaling
kubectl scale deployment/processor --replicas=3 -n aurora-logs

# Update HPA limits
kubectl edit hpa processor-hpa -n aurora-logs
```

## Support

For issues or questions:
1. Check pod logs for errors
2. Run health check script
3. Review AWS IAM permissions
4. Verify network connectivity between services