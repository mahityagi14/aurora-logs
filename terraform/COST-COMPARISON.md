# Cost Comparison: EKS vs ECS

## Monthly Cost Breakdown

### EKS Setup
| Component | Cost | Notes |
|-----------|------|-------|
| EKS Control Plane | $72.00 | $0.10/hour × 24 × 30 |
| Worker Nodes (2 × t4g.small) | $24.43 | $0.0168/hour × 2 × 24 × 30 |
| **Total** | **$96.43** | |

### ECS with EC2 Setup
| Component | Cost | Notes |
|-----------|------|-------|
| ECS Control Plane | $0.00 | Free |
| EC2 Instances (1 × t4g.small POC) | $12.22 | $0.0168/hour × 1 × 24 × 30 |
| EC2 Instances (2 × t4g.medium Prod) | $48.86 | $0.0336/hour × 2 × 24 × 30 |
| **Total POC** | **$12.22** | Single instance |
| **Total Production** | **$48.86** | Two instances |

### Savings: 
- POC: $84.21/month (87% reduction)
- Production: $47.57/month (49% reduction)

## Service Resource Allocation

### ECS Fargate Tasks
| Service | vCPU | Memory | Instance Type | Monthly Cost |
|---------|------|--------|---------------|--------------|
| Discovery | 0.25 | 0.5 GB | Fargate | $1.04 |
| Processor | 0.5 | 1 GB | Fargate Spot | $0.65 |
| Kafka | 0.5 | 1 GB | Fargate | $2.17 |
| OpenObserve | 0.5 | 1 GB | Fargate | $2.17 |
| **Total** | **1.75** | **3.5 GB** | | **$6.03** |

### Additional Costs (Same for both)
| Component | Cost | Notes |
|-----------|------|-------|
| Valkey (cache.t4g.micro) | $11.52 | Shared between EKS/ECS |
| Data Transfer | ~$5-10 | Depends on usage |
| CloudWatch Logs | ~$5 | Log storage |

## Annual Comparison

| Platform | Monthly | Annual | 3-Year TCO |
|----------|---------|--------|------------|
| EKS | $96.43 | $1,157.16 | $3,471.48 |
| ECS | $6.33 | $75.96 | $227.88 |
| **Savings** | **$90.10** | **$1,081.20** | **$3,243.60** |

## Why ECS is Cheaper

1. **No Control Plane Cost**: EKS charges $72/month, ECS is free
2. **Fargate Pricing**: Pay only for actual CPU/Memory used
3. **Fargate Spot**: 70% discount for interruptible workloads
4. **Right-Sizing**: Fargate allows precise resource allocation
5. **No Over-Provisioning**: No idle capacity like EC2 nodes

## When to Use Each

### Use EKS When:
- You need Kubernetes-specific features
- You have existing Kubernetes expertise
- You need complex orchestration
- You're running 50+ containers

### Use ECS When:
- Cost is a primary concern
- You want AWS-native integration
- You have simpler orchestration needs
- You're running <50 containers

## Recommendation

For the Aurora Log System with 4 services, **ECS with Fargate Spot** provides:
- 93% cost savings
- Simpler operations
- Better AWS integration
- Automatic scaling
- No infrastructure management