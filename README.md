# Aurora Log System

A distributed log collection and analysis system for AWS Aurora databases.

## Architecture

- **Discovery Service**: Finds Aurora instances and monitors log files
- **Processor Service**: Downloads and processes log files  
- **Kafka**: Message queue for reliable delivery
- **OpenObserve**: Log storage and analytics

## Quick Start

### Prerequisites

- AWS Account with Aurora instances
- EKS cluster running
- kubectl configured
- AWS CLI configured

### Deploy Infrastructure

```bash
cd infrastructure/terraform
terraform init
terraform apply
```

### Deploy Application

```bash
./deploy.sh poc apply
```

### Check Status

```bash
./deploy.sh poc status
```

### Access OpenObserve

URL: http://openobserve-alb-355407172.us-east-1.elb.amazonaws.com
- Username: admin@example.com
- Password: Complexpass#123

## Directory Structure

```
├── services/           # Microservices
│   ├── discovery/     # Discovery service
│   └── processor/     # Processor service
├── infrastructure/    # Infrastructure code
│   ├── terraform/     # AWS infrastructure
│   ├── kubernetes/    # K8s manifests
│   └── iam/          # IAM policies
├── ci-cd/            # CI/CD configuration
├── tests/            # Integration tests
├── docs/             # Documentation
└── deploy.sh         # Deployment script
```

## Development

### Build Services

```bash
cd services/discovery
docker build -t discovery .

cd services/processor  
docker build -t processor .
```

### Run Tests

```bash
cd tests
./test-all.sh
```

## Configuration

Edit `infrastructure/kubernetes/02-config-secrets.yaml` to change:
- DynamoDB table names
- S3 bucket
- Redis/Valkey endpoint
- Discovery interval
- Batch sizes

## Monitoring

- Each service exposes metrics on port 9090
- Logs are in JSON format
- OpenObserve provides search and dashboards

## License

Copyright 2025 - All rights reserved