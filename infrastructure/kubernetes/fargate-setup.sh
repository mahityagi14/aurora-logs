#!/bin/bash

# Aurora Log System - Fargate Profile Setup
# This script creates Fargate profiles for cost-optimized processing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME="${EKS_CLUSTER_NAME:-aurora-cluster}"
NAMESPACE="aurora-logs"
AWS_REGION="${AWS_REGION:-us-east-1}"
FARGATE_POD_EXECUTION_ROLE_NAME="AuroraLogsFargatePodExecutionRole"

echo -e "${BLUE}=== Aurora Log System Fargate Setup ===${NC}"
echo -e "${BLUE}Setting up Fargate profiles for cost optimization...${NC}\n"

# Check prerequisites
if ! command -v eksctl &> /dev/null; then
    echo -e "${RED}Error: eksctl is not installed${NC}"
    echo "Install eksctl: https://eksctl.io/installation/"
    exit 1
fi

# Create Fargate Pod Execution Role if it doesn't exist
echo -e "${BLUE}1. Creating Fargate Pod Execution Role...${NC}"
ROLE_EXISTS=$(aws iam get-role --role-name $FARGATE_POD_EXECUTION_ROLE_NAME 2>/dev/null || echo "")

if [ -z "$ROLE_EXISTS" ]; then
    eksctl create iamserviceaccount \
        --cluster $CLUSTER_NAME \
        --region $AWS_REGION \
        --name fargate-pod-execution-sa \
        --namespace $NAMESPACE \
        --attach-policy-arn arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy \
        --override-existing-serviceaccounts \
        --approve
    
    echo -e "${GREEN}✓ Fargate Pod Execution Role created${NC}\n"
else
    echo -e "${YELLOW}Fargate Pod Execution Role already exists${NC}\n"
fi

# Create Fargate profile for processor slaves
echo -e "${BLUE}2. Creating Fargate profile for processor slaves...${NC}"
eksctl create fargateprofile \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --name aurora-processor-slaves \
    --namespace $NAMESPACE \
    --labels app=processor,role=slave \
    --tags "Environment=production,CostCenter=aurora-logs,Purpose=log-processing" || {
    echo -e "${YELLOW}Fargate profile aurora-processor-slaves already exists or failed${NC}"
}

# Create Fargate profile for Fluent Bit K8s logs (optional)
echo -e "${BLUE}3. Creating Fargate profile for Fluent Bit (optional)...${NC}"
eksctl create fargateprofile \
    --cluster $CLUSTER_NAME \
    --region $AWS_REGION \
    --name aurora-fluent-bit \
    --namespace $NAMESPACE \
    --labels app=fluent-bit-k8s \
    --tags "Environment=production,CostCenter=aurora-logs,Purpose=k8s-logging" || {
    echo -e "${YELLOW}Fargate profile aurora-fluent-bit already exists or failed${NC}"
}

# List all Fargate profiles
echo -e "\n${BLUE}4. Current Fargate profiles:${NC}"
eksctl get fargateprofile --cluster $CLUSTER_NAME --region $AWS_REGION

# Patch deployments for Fargate compatibility
echo -e "\n${BLUE}5. Patching deployments for Fargate...${NC}"

# Remove resource limits for Fargate pods (Fargate manages resources)
kubectl patch deployment processor-slaves -n $NAMESPACE --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/template/spec/containers/0/resources/limits"
  }
]' 2>/dev/null || echo -e "${YELLOW}Could not patch processor-slaves limits${NC}"

# Add Fargate annotations
kubectl patch deployment processor-slaves -n $NAMESPACE --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/metadata/annotations",
    "value": {
      "eks.amazonaws.com/compute-type": "fargate",
      "kubernetes.io/ingress-bandwidth": "10M",
      "kubernetes.io/egress-bandwidth": "10M"
    }
  }
]' 2>/dev/null || echo -e "${YELLOW}Could not add Fargate annotations${NC}"

echo -e "\n${BLUE}6. Cost optimization settings:${NC}"
cat << EOF
Fargate Pricing (us-east-1):
- vCPU: \$0.04048 per vCPU per hour
- Memory: \$0.004445 per GB per hour

Processor Slave Configuration:
- CPU Request: 50m (0.05 vCPU) = \$0.002024/hour
- Memory Request: 128Mi (0.125 GB) = \$0.000556/hour
- Total per pod: ~\$0.0026/hour (~\$1.87/month if running 24/7)

With scale-to-zero:
- 0 pods when idle = \$0
- Auto-scales based on load
- Typical usage: 2-4 hours/day = \$0.15-\$0.30/month per pod

Estimated monthly cost with Fargate:
- Master pod (EC2): ~\$5/month
- Slave pods (Fargate): ~\$5-15/month based on usage
- Total processor cost: ~\$10-20/month (vs \$50+ without optimization)
EOF

echo -e "\n${GREEN}=== Fargate Setup Complete ===${NC}"
echo -e "${BLUE}Next steps:${NC}"
echo "1. Deploy the processor-slaves deployment: kubectl apply -f 16-processor-master-slave.yaml"
echo "2. Monitor Fargate pods: kubectl get pods -n aurora-logs -o wide"
echo "3. Check Fargate logs: kubectl logs -n aurora-logs -l role=slave"
echo "4. Monitor costs in AWS Cost Explorer with tags: CostCenter=aurora-logs"