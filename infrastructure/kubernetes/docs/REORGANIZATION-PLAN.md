# Kubernetes Folder Reorganization Plan

## Current Issues
1. Duplicate configurations for processor, kafka, and autoscaling
2. Separate "optimized" versions instead of single source of truth
3. Too many numbered files (20+)
4. Multiple deployment scripts doing similar things

## Proposed Structure

### Core Configurations (00-10)
- `00-namespace.yaml` - Keep as is
- `01-secrets.yaml` - Keep as is  
- `02-configmaps.yaml` - Keep as is
- `03-storage.yaml` - Keep as is
- `04-valkey.yaml` - Merge with optimized resources
- `05-kafka.yaml` - Use optimized version as default
- `06-openobserve.yaml` - Merge with optimized resources
- `07-discovery.yaml` - Merge with optimized resources
- `08-processor.yaml` - Use master-slave as default
- `09-fluent-bit-config.yaml` - Keep as is
- `10-autoscaling.yaml` - Use cost-optimized version

### Operational Configurations (11-14)
- `11-network-policies.yaml` - Keep as is
- `12-pod-disruption-budgets.yaml` - Keep as is
- `13-resource-quotas.yaml` - Keep as is
- `14-monitoring.yaml` - Combine K8s logs + dashboards

### Scripts (not numbered)
- `setup.sh` - Combined setup script
- `deploy.sh` - Single deployment script with options
- `cleanup.sh` - Keep as is
- `Makefile` - Simplified commands

### Documentation (docs/)
- `README.md` - Main readme
- `docs/cost-optimization.md`
- `docs/production-guide.md`
- `docs/troubleshooting.md`

### Archive (archive/)
- Move old/duplicate versions here

## Files to Remove/Merge
1. Remove `15-optimized-resources.yaml` - merge into individual services
2. Remove `16-processor-master-slave.yaml` - make it default `08-processor.yaml`
3. Remove `17-cost-optimized-autoscaling.yaml` - make it default `10-autoscaling.yaml`
4. Remove `20-kafka-optimized.yaml` - make it default `05-kafka.yaml`
5. Combine `18-fargate-setup.sh` into main setup script
6. Merge `19-openobserve-dashboards.yaml` with `14-fluent-bit-k8s-logs.yaml`

## Result
- From 20+ numbered files → 14 files
- Single source of truth for each service
- Cost-optimized by default
- Cleaner, more maintainable structure