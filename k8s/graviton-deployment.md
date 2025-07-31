# Graviton ARM64 Deployment

## Why Graviton?

1. **Cost Savings**: Up to 40% cheaper than equivalent x86 instances
2. **Better Performance**: Graviton processors provide better price-performance
3. **Energy Efficient**: Lower power consumption
4. **Consistent with Infrastructure**: We're already using Graviton for Valkey (cache.t4g.micro)

## Changes Made

### 1. Node Group Configuration
- Deleted x86 node group (t3.small)
- Created ARM64 node group with:
  - Instance type: **t4g.small** (Graviton)
  - AMI type: **AL2023_ARM_64_STANDARD**
  - Node count: 2 (min: 1, max: 3)

### 2. Kubernetes Configuration
- Updated values-poc.yaml with ARM64 node selector:
  ```yaml
  nodeSelector:
    kubernetes.io/arch: "arm64"
    node.kubernetes.io/instance-type: "t4g.small"
  ```

### 3. Deployment Manifests
- All deployment manifests already have ARM64 node selector
- Docker images built by Jenkins support multi-arch (linux/amd64, linux/arm64)

## Cost Comparison

| Instance Type | vCPU | Memory | On-Demand Price/hr | Monthly Cost (2 nodes) |
|---------------|------|--------|-------------------|----------------------|
| t3.small (x86) | 2 | 2 GiB | $0.0208 | ~$30.24 |
| t4g.small (ARM) | 2 | 2 GiB | $0.0168 | ~$24.43 |
| **Savings** | - | - | **19%** | **~$5.81/month** |

## Current Status

- Node group: **aurora-logs-poc-arm64-nodes** (CREATING)
- Expected time: 5-10 minutes
- Once active, all pods will be scheduled on Graviton instances

## Benefits for Aurora Log System

1. **Discovery Service**: Lower latency for RDS API calls
2. **Processor Service**: Better throughput for log processing
3. **Kafka**: Improved message handling performance
4. **OpenObserve**: Faster query processing

## Next Steps

1. Wait for node group to be ACTIVE
2. Verify nodes are Ready
3. Deploy applications
4. Monitor performance metrics