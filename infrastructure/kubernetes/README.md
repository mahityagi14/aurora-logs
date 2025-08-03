# Aurora Log System - Kubernetes Deployment

Simplified, cost-optimized Kubernetes deployment for the Aurora Log System.

## Quick Start

```bash
# 1. Setup IAM roles (one-time)
./setup-iam.sh

# 2. Deploy everything
./deploy.sh
```

## File Structure

| File | Description |
|------|-------------|
| **00-04: Base Infrastructure** |
| `00-namespace.yaml` | Namespace and service accounts with IAM roles |
| `01-secrets.yaml` | All credentials and authentication |
| `02-configmaps.yaml` | Application configuration |
| `03-storage.yaml` | Persistent volume claims |
| `04-valkey.yaml` | Redis-compatible cache (optimized) |
| **05-08: Core Services** |
| `05-kafka.yaml` | Message broker - single node, cost-optimized |
| `06-openobserve.yaml` | Log analytics platform (optimized) |
| `07-discovery.yaml` | Aurora log discovery service (optimized) |
| `08-processor.yaml` | Master-slave processor architecture |
| **09-13: Operations** |
| `09-fluent-bit-config.yaml` | Fluent Bit parsers and configuration |
| `10-autoscaling.yaml` | HPA with scale-to-zero for slaves |
| `11-network-policies.yaml` | Network security policies |
| `12-policies.yaml` | Pod disruption budgets & resource quotas |
| `13-monitoring.yaml` | K8s logs collection and dashboards |

## Key Features

✅ **Cost Optimized** - 73% lower costs (~$60/month vs $305/month)  
✅ **Master-Slave Architecture** - Single master + auto-scaled slaves  
✅ **Scale-to-Zero** - Slaves shutdown when idle  
✅ **Fluent Bit Integration** - Flexible log parsing  
✅ **K8s Log Collection** - Centralized logging to S3  
✅ **Production Ready** - Health checks, monitoring, security  

## Architecture

```
Aurora RDS → Discovery → Kafka → Processor Master → Processor Slaves → Fluent Bit → OpenObserve
                                        ↓                                              ↓
                                   DynamoDB                                    S3 (K8s logs)
```

## Common Operations

```bash
# Check status
make status

# View logs
make logs        # Processor master logs
make logs-k8s    # K8s log collector

# Monitor costs
make cost

# Scale manually
kubectl scale deployment/processor-slaves --replicas=3 -n aurora-logs

# Setup Fargate (optional)
make fargate
```

## Access OpenObserve

```bash
# Port forward
kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080

# Access UI
http://localhost:5080
Username: admin@example.com
Password: Complexpass#123
```

## Cost Breakdown

| Component | Resources | Est. Cost/Month |
|-----------|-----------|-----------------|
| Discovery | 50m CPU, 128Mi RAM | ~$3 |
| Processor Master | 100m CPU, 256Mi RAM | ~$5 |
| Processor Slaves | 0-10 pods (scale-to-zero) | $0-15 |
| Kafka | 200m CPU, 1Gi RAM | ~$10 |
| OpenObserve | 500m CPU, 2Gi RAM | ~$20 |
| Valkey | 50m CPU, 128Mi RAM | ~$3 |
| Storage | 15Gi total | ~$2 |
| K8s Logs S3 | ~50GB/month | ~$1 |
| **Total (idle)** | | **~$44** |
| **Total (active)** | | **~$60-80** |

## Documentation

- [Cost Optimization Guide](docs/COST-OPTIMIZATION-SUMMARY.md)
- [Production Readiness](docs/PRODUCTION-READINESS.md)
- [Deployment Guide](docs/DEPLOYMENT-GUIDE.md)

## Cleanup

```bash
# Remove all resources
make clean

# Remove IAM roles
make clean-iam
```