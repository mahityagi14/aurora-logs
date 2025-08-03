# Aurora Log System - Kubernetes Deployment

This directory contains the Kubernetes manifests for deploying the Aurora Log System with OpenTelemetry (OTEL) support.

## Architecture Overview

The system consists of the following components:
- **Discovery Service**: Discovers Aurora log files from S3
- **Kafka**: Message broker for log processing pipeline
- **Processor**: Processes logs (Master-Slave architecture)
- **OpenObserve**: Log storage and analytics
- **Valkey (Redis)**: Caching layer
- **OTEL Collector**: Collects traces, metrics, and logs
- **Fluent Bit**: Log parsing and forwarding

## Deployment

### Prerequisites
- Kubernetes cluster with EKS
- Node group named `aurora-node-2` 
- kubectl configured to access the cluster
- Container images built and pushed to ECR

### Quick Deploy

```bash
# Deploy everything
./deploy-aurora.sh

# Clean up everything
./cleanup-aurora.sh
```

### Manual Deployment Order

1. **Namespace and RBAC**: `00-namespace.yaml`
2. **Secrets**: `01-secrets.yaml`
3. **ConfigMaps**: `02-configmaps.yaml`
4. **Storage**: `03-storage.yaml`
5. **Valkey**: `04-valkey.yaml`
6. **Kafka**: `05-kafka.yaml`
7. **OpenObserve**: `06-openobserve.yaml`
8. **Discovery**: `07-discovery.yaml`
9. **Processor**: `08-processor.yaml`
10. **Fluent Bit Config**: `09-fluent-bit-config.yaml`
11. **Autoscaling**: `10-autoscaling.yaml`
12. **Network Policies**: `11-network-policies.yaml`
13. **Pod Policies**: `12-policies.yaml`
14. **Monitoring**: `13-monitoring.yaml`
15. **OTEL Collector**: `14-otel-collector.yaml`
16. **Fluent Bit DaemonSet**: `15-fluent-bit-daemonset.yaml`

## Key Features

### Node Affinity
All components are configured to run exclusively on `aurora-node-2` using node affinity:
```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: eks.amazonaws.com/nodegroup
          operator: In
          values:
          - aurora-node-2
```

### OpenTelemetry Integration
- OTEL Collector deployed for trace, metric, and log collection
- All services configured with OTEL environment variables
- Traces exported to OpenObserve
- Metrics scraped via Prometheus protocol

### Cost Optimization
- Minimal resource requests/limits
- Single-node Kafka deployment
- Scale-to-zero processor slaves
- Efficient storage usage

## Access Services

```bash
# OpenObserve UI
kubectl port-forward -n aurora-logs svc/openobserve-service 5080:5080
# Access at http://localhost:5080
# Credentials: admin@example.com / Complexpass#123

# OTEL Collector (for sending traces)
kubectl port-forward -n aurora-logs svc/otel-collector 4317:4317

# Kafka
kubectl port-forward -n aurora-logs svc/kafka-service 9092:9092
```

## Monitoring

Check deployment status:
```bash
kubectl get all -n aurora-logs
kubectl get pods -n aurora-logs -o wide
```

View logs:
```bash
kubectl logs -n aurora-logs deployment/processor-master
kubectl logs -n aurora-logs deployment/otel-collector
```

## Troubleshooting

1. **Pods not scheduling on aurora-node-2**:
   - Verify node exists: `kubectl get nodes -l eks.amazonaws.com/nodegroup=aurora-node-2`
   - Check pod events: `kubectl describe pod <pod-name> -n aurora-logs`

2. **OTEL Collector not receiving data**:
   - Check service endpoint: `kubectl get svc otel-collector -n aurora-logs`
   - Verify OTEL environment variables in pods
   - Check collector logs: `kubectl logs deployment/otel-collector -n aurora-logs`

3. **Fluent Bit issues**:
   - Check DaemonSet status: `kubectl get ds fluent-bit -n aurora-logs`
   - View Fluent Bit logs: `kubectl logs ds/fluent-bit -n aurora-logs`

## Configuration

### OTEL Configuration
Located in `14-otel-collector.yaml`:
- Receivers: OTLP (gRPC/HTTP), Prometheus
- Processors: Batch, Memory Limiter, Resource, K8s Attributes
- Exporters: OpenObserve (traces, metrics, logs)

### Fluent Bit Configuration
Located in `09-fluent-bit-config.yaml`:
- Input: Forward protocol on port 24224
- Parsers: Aurora error, slow query, and general logs
- Output: OpenObserve HTTP endpoint

## Archive Directory

The `archive/` directory contains previous versions and experimental configurations for reference.