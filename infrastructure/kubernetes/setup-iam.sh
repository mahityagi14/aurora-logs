#!/bin/bash

# Aurora Log System - IAM Setup Script
# This script creates the necessary IAM roles and policies for EKS Pod Identity

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ACCOUNT_ID="072006186126"
AWS_REGION="us-east-1"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-aurora-cluster}"
NAMESPACE="aurora-logs"

echo -e "${BLUE}=== Aurora Log System IAM Setup ===${NC}"
echo -e "${BLUE}Setting up IAM roles and policies...${NC}\n"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Verify AWS credentials
aws sts get-caller-identity &> /dev/null || {
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
}

# Get EKS cluster OIDC provider
echo -e "${BLUE}Getting EKS cluster OIDC provider...${NC}"
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text 2>/dev/null | sed -e "s/^https:\/\///")

if [ -z "$OIDC_PROVIDER" ] || [ "$OIDC_PROVIDER" == "None" ]; then
    echo -e "${RED}Error: Could not get OIDC provider for cluster $CLUSTER_NAME${NC}"
    echo -e "${YELLOW}Please ensure you're connected to the correct EKS cluster${NC}"
    exit 1
fi

echo -e "${GREEN}OIDC Provider: $OIDC_PROVIDER${NC}\n"

# Create Discovery Service IAM Role
echo -e "${BLUE}Creating Discovery Service IAM Role...${NC}"

# Create trust policy for Discovery Service
cat > /tmp/discovery-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:discovery-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create or update the role
aws iam create-role \
    --role-name AuroraLogDiscoveryRole \
    --assume-role-policy-document file:///tmp/discovery-trust-policy.json \
    --description "Role for Aurora Log Discovery Service" 2>/dev/null || \
aws iam update-assume-role-policy \
    --role-name AuroraLogDiscoveryRole \
    --policy-document file:///tmp/discovery-trust-policy.json

# Create policy for Discovery Service
cat > /tmp/discovery-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:DescribeDBClusters",
                "rds:DescribeDBInstances",
                "rds:DescribeDBLogFiles",
                "rds:ListTagsForResource"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:BatchWriteItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/aurora-log-tracking",
                "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/aurora-instance-metadata"
            ]
        }
    ]
}
EOF

# Attach policy to Discovery role
aws iam put-role-policy \
    --role-name AuroraLogDiscoveryRole \
    --policy-name discovery-policy \
    --policy-document file:///tmp/discovery-policy.json

echo -e "${GREEN}✓ Discovery Service IAM Role created${NC}\n"

# Create Processor Service IAM Role
echo -e "${BLUE}Creating Processor Service IAM Role...${NC}"

# Create trust policy for Processor Service
cat > /tmp/processor-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:processor-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create or update the role
aws iam create-role \
    --role-name AuroraLogProcessorRole \
    --assume-role-policy-document file:///tmp/processor-trust-policy.json \
    --description "Role for Aurora Log Processor Service" 2>/dev/null || \
aws iam update-assume-role-policy \
    --role-name AuroraLogProcessorRole \
    --policy-document file:///tmp/processor-trust-policy.json

# Create policy for Processor Service
cat > /tmp/processor-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "rds:DownloadDBLogFilePortion"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::company-aurora-logs-poc",
                "arn:aws:s3:::company-aurora-logs-poc/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query"
            ],
            "Resource": [
                "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/aurora-log-tracking",
                "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/aurora-log-processing-jobs"
            ]
        }
    ]
}
EOF

# Attach policy to Processor role
aws iam put-role-policy \
    --role-name AuroraLogProcessorRole \
    --policy-name processor-policy \
    --policy-document file:///tmp/processor-policy.json

echo -e "${GREEN}✓ Processor Service IAM Role created${NC}\n"

# Create OpenObserve Service IAM Role
echo -e "${BLUE}Creating OpenObserve Service IAM Role...${NC}"

# Create trust policy for OpenObserve Service
cat > /tmp/openobserve-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:openobserve-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create or update the role
aws iam create-role \
    --role-name AuroraLogOpenObserveRole \
    --assume-role-policy-document file:///tmp/openobserve-trust-policy.json \
    --description "Role for OpenObserve Service" 2>/dev/null || \
aws iam update-assume-role-policy \
    --role-name AuroraLogOpenObserveRole \
    --policy-document file:///tmp/openobserve-trust-policy.json

# Create policy for OpenObserve Service
cat > /tmp/openobserve-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::company-aurora-logs-poc",
                "arn:aws:s3:::company-aurora-logs-poc/*"
            ]
        }
    ]
}
EOF

# Attach policy to OpenObserve role
aws iam put-role-policy \
    --role-name AuroraLogOpenObserveRole \
    --policy-name openobserve-policy \
    --policy-document file:///tmp/openobserve-policy.json

echo -e "${GREEN}✓ OpenObserve Service IAM Role created${NC}\n"

# Clean up temporary files
rm -f /tmp/discovery-trust-policy.json /tmp/discovery-policy.json
rm -f /tmp/processor-trust-policy.json /tmp/processor-policy.json
rm -f /tmp/openobserve-trust-policy.json /tmp/openobserve-policy.json

# Display summary
echo -e "${BLUE}=== IAM Setup Summary ===${NC}"
echo -e "${GREEN}✓ All IAM roles and policies created successfully!${NC}\n"
echo -e "Roles created:"
echo -e "  - ${GREEN}AuroraLogDiscoveryRole${NC} for discovery-sa"
echo -e "  - ${GREEN}AuroraLogProcessorRole${NC} for processor-sa"
echo -e "  - ${GREEN}AuroraLogOpenObserveRole${NC} for openobserve-sa"
echo -e "\n${YELLOW}Note: The Kubernetes service accounts are configured to use these roles via annotations${NC}"