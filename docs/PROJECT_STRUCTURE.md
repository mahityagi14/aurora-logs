# Aurora Log System - Project Structure

## Directory Layout

```
aurora-log-system-main/
├── discovery/              # Discovery service (Go)
│   ├── Dockerfile         # Multi-stage build for ARM64
│   ├── main.go           # Discovers Aurora instances and log files
│   ├── main_test.go      # Unit tests
│   └── go.mod/go.sum     # Go dependencies
│
├── processor/             # Processor service (Go)
│   ├── Dockerfile        # Multi-stage build for ARM64
│   ├── main.go          # Downloads and processes logs
│   ├── main_test.go     # Unit tests
│   └── go.mod/go.sum    # Go dependencies
│
├── k8s/                  # Kubernetes manifests
│   ├── setup.yaml       # Namespace and RBAC setup
│   ├── configmaps/      # Application configuration
│   │   ├── app-config.yaml      # Main app config
│   │   ├── kafka-config.yaml    # Kafka server config
│   │   └── graceful-shutdown.yaml
│   ├── secrets/         # Sensitive configuration
│   │   ├── app-secrets.yaml     # AWS credentials (if needed)
│   │   └── openobserve-secret.yaml
│   ├── deployments/     # Application deployments
│   │   ├── discovery-deployment.yaml
│   │   ├── processor-deployment.yaml
│   │   ├── kafka-deployment.yaml      # Confluent Kafka
│   │   └── openobserve-deployment.yaml
│   ├── services/        # Kubernetes services
│   │   ├── kafka-service.yaml
│   │   ├── kafka-broker-service.yaml
│   │   ├── openobserve-service.yaml
│   │   └── openobserve-lb.yaml
│   ├── hpa/            # Auto-scaling configuration
│   │   └── autoscaling.yaml
│   ├── deploy-aurora-logs.sh    # Deployment script
│   └── values-*.yaml           # Environment configs
│
├── eks-terraform/       # EKS infrastructure (Terraform)
│   ├── main.tf         # Main EKS configuration
│   ├── variables.tf    # Variable definitions
│   ├── node-groups.tf  # EKS node configuration
│   ├── ebs-csi-iam.tf  # EBS CSI driver
│   ├── k8s-logs-bucket.tf # S3 bucket for logs
│   └── modules/        # Terraform modules
│
├── iam/                # IAM policies
│   ├── discovery-policy.json
│   ├── processor-policy.json
│   └── openobserve-policy.json
│
├── tests/              # Integration tests
│   ├── integration_test.go
│   ├── performance_test.go
│   └── test-all.sh
│
├── jenkins/            # CI/CD configuration
│   └── multibranch-pipeline.groovy
│
├── Jenkinsfile         # Jenkins pipeline
├── Makefile           # Build commands
├── README.md          # Main documentation
└── CLAUDE.md          # AI assistant context
```

## Key Components

### 1. **Discovery Service** (`discovery/`)
- Discovers Aurora instances via RDS API
- Monitors log files for changes
- Publishes to Kafka topics
- Uses Redis/Valkey for API caching

### 2. **Processor Service** (`processor/`)
- Consumes from Kafka
- Downloads logs from RDS
- Parses and enriches log data
- Sends to OpenObserve

### 3. **Message Queue** (Kafka - using Confluent image)
- Topics: `aurora-logs-error`, `aurora-logs-slowquery`
- Ensures reliable message delivery
- Handles backpressure

### 4. **Storage & Analytics** (OpenObserve)
- Stores logs in S3
- Provides search and visualization
- Accessible via ALB

### 5. **Infrastructure** (`eks-terraform/`)
- EKS cluster with ARM64 nodes
- DynamoDB tables for tracking
- ElastiCache Valkey for caching
- S3 bucket for log storage

## Data Flow

1. Discovery → Kafka → Processor → OpenObserve → S3
2. All services run on EKS (ARM64/Graviton2)
3. Uses AWS Pod Identity for authentication

## Deployment

```bash
# Deploy infrastructure
cd eks-terraform
terraform apply

# Deploy application
cd ../k8s
./deploy-aurora-logs.sh poc
```

## Environment Files

- `values-poc.yaml` - POC environment config
- `values-production.yaml` - Production config template
- `terraform.tfvars.poc` - Infrastructure variables