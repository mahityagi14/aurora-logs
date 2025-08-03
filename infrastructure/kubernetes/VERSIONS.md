# Aurora Log System - Component Versions

This document lists all the container images and their versions used in the Aurora Log System deployment.

## Architecture Requirements

**IMPORTANT**: All images are ARM64 architecture to run on AWS Graviton (t4g) instances.
- Target node: aurora-node-2 (t4g.2xlarge - ARM64)
- All images must use ARM64 variants
- Do not use AMD64/x86_64 images as they will fail to run

## Third-Party Components (ARM64 Architecture)

### Observability Stack
- **OpenObserve**: `openobserve/openobserve:v0.15.0-rc4-arm64`
  - Log analytics and storage platform
  - S3-backed storage with Prometheus compatibility
  - ARM64 architecture for t4g instances

- **OpenTelemetry Collector**: `otel/opentelemetry-collector-contrib:0.131.1-arm64`
  - Trace, metric, and log collection
  - Configured with OTLP receivers and OpenObserve exporters
  - ARM64 architecture for optimal performance on Graviton

- **Fluent Bit**: `fluent/fluent-bit:4.0.5-arm64`
  - Log parsing and forwarding
  - Aurora log parser configurations
  - Native ARM64 build

### Data Infrastructure
- **Kafka**: `bitnami/kafka:4.0.0` (ARM64)
  - Message broker using KRaft mode (no Zookeeper)
  - Single-node deployment for cost optimization
  - Bitnami image with ARM64 support

- **Valkey (Redis)**: `valkey/valkey:8.1.3` (ARM64)
  - In-memory cache
  - Used for deduplication and temporary storage
  - Native ARM64 support

### Utility Images
- **curl**: `curlimages/curl:latest`
  - Used in dashboard import job
  - Minimal image for HTTP operations

## Aurora Application Images

### Core Services
- **Discovery Service**: `072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:discovery-latest`
  - Discovers Aurora log files from S3
  - Tracks processing state in DynamoDB

- **Processor Service**: `aurora-processor:latest`
  - Processes Aurora logs in master-slave architecture
  - Consumes from Kafka and forwards to OpenObserve

## Version Policy

### Production Recommendations
1. **Pin specific versions** instead of using `latest` tags
2. **Test upgrades** in a staging environment first
3. **Review changelogs** before upgrading major versions

### Update Strategy
- **Security patches**: Apply immediately
- **Minor versions**: Test and apply monthly
- **Major versions**: Evaluate features and breaking changes

## Compatibility Matrix

| Component | Version | Architecture | Compatible With | Notes |
|-----------|---------|--------------|----------------|-------|
| OpenObserve | v0.15.0-rc4-arm64 | ARM64 | S3, Prometheus | RC version - ARM64 optimized |
| OTEL Collector | 0.131.1-arm64 | ARM64 | OpenObserve v0.15+ | Latest stable with OTLP/gRPC |
| Fluent Bit | 4.0.5-arm64 | ARM64 | All components | Latest v4 with improved performance |
| Kafka | 4.0.0 | ARM64 | All components | Bitnami Kafka 4.0 with KRaft |
| Valkey | 8.1.3 | ARM64 | Redis protocol 7.2 | Native ARM64 build |

## Image Sources

### Public Images
- OpenObserve: [Docker Hub](https://hub.docker.com/r/openobserve/openobserve)
- OTEL Collector: [Docker Hub](https://hub.docker.com/r/otel/opentelemetry-collector-contrib)
- Fluent Bit: [Docker Hub](https://hub.docker.com/r/fluent/fluent-bit)
- Valkey: [Docker Hub](https://hub.docker.com/r/valkey/valkey)
- curl: [Docker Hub](https://hub.docker.com/r/curlimages/curl)

### Private Images (ECR)
- Discovery Service: `072006186126.dkr.ecr.us-east-1.amazonaws.com/aurora-log-system:discovery-latest`
- Processor Service: Build from source and push to ECR
- Kafka: Build from source with custom configurations

## Build Instructions

### Custom Kafka Image
```dockerfile
FROM bitnami/kafka:latest
# Add custom configurations for Aurora workload
# Enable KRaft mode by default
```

### Aurora Processor Image
```dockerfile
FROM golang:1.21-alpine AS builder
# Build processor binary
FROM alpine:latest
# Copy binary and run
```

## Security Considerations

1. **Scan all images** for vulnerabilities before deployment
2. **Use specific versions** to ensure reproducible deployments
3. **Update base images** regularly for security patches
4. **Implement image signing** for production deployments

## Upgrade Notes

### OpenObserve v0.15.0-rc4
- Currently using Release Candidate
- Upgrade to stable v0.15.0 when released
- Check for API compatibility changes

### Fluent Bit 4.0.5-arm64
- Major version 4.0 with significant performance improvements
- Native ARM64 build for Graviton processors
- Enhanced OpenTelemetry support
- Improved memory management

### OTEL Collector 0.131.1-arm64
- Latest stable version with enhanced features
- Native ARM64 architecture
- Improved k8sattributes processor
- Better memory efficiency on ARM

### Kafka 4.0.0 (Bitnami)
- Kafka 3.8.x based image
- Full KRaft mode support
- Optimized for ARM64 architecture
- Reduced memory footprint