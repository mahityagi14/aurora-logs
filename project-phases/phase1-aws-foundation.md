# Phase 1: AWS Foundation Setup for EKS - Console Guide (2025)

## Overview
This guide walks through setting up the foundation AWS infrastructure for the Aurora MySQL Log Processing POC using Apache Kafka 4.0 on EKS. All steps are performed through the AWS Management Console following the latest 2025 AWS documentation patterns.

**Key Architecture Decisions:**
- Uses AWS Graviton 4 instances for production readiness
- Public subnets for simplified POC deployment
- No IRSA/OIDC configuration - pods will use node group IAM role permissions
- No CloudWatch logging - RDS logs fetched via API, EKS logs sent to OpenObserve
- EKS cluster with custom configuration and managed node groups
- Security groups for Kubernetes workloads
- S3 bucket for processed logs
- Jenkins CI/CD on EC2 for ARM64 image builds

## POC vs Production Configuration

| Component | POC Configuration | Production Configuration | Rationale |
|-----------|------------------|-------------------------|-----------|
| **EKS Node Instance Type** | t4g.medium (2 vCPU, 4GB) | m8g.8xlarge (32 vCPU, 128GB) or r8g.8xlarge | POC uses burstable Graviton 2 for cost; Production uses Graviton 4 for performance |
| **Node Group Size** | 3 nodes (min: 2, max: 6) | 20 nodes (min: 10, max: 50) | POC minimal for testing; Production sized for 316+ RDS instances |
| **Availability Zones** | 3 AZs | 3+ AZs | Both ensure high availability |
| **Network** | Public subnets | Private subnets with NAT | POC simplified networking; Production secure |
| **IAM Permissions** | All in node role | All in node role | No IRSA for simplicity |
| **Security Groups** | Open for POC | Restrictive | POC allows easier debugging |
| **S3 Bucket** | Single region | Multi-region replication | POC simple; Production resilient |
| **Cost** | ~$150/month | ~$15,000/month | Reflects resource scaling |

## Prerequisites
- AWS Account with appropriate permissions
- Existing VPC with at least 3 public subnets across different AZs
- Access to AWS Management Console
- Note your AWS region and account ID
- GitHub repository: `https://github.com/anshtyagi14/aurora-log-system.git`

## Step 1: Create IAM Roles and Policies

### 1.1 Create EKS Cluster IAM Role

This role allows EKS to manage AWS resources on your behalf.

1. Navigate to **IAM Console** → **Roles** → **Create role**
2. **Select trusted entity**:
   - Trusted entity type: **AWS service**
   - Use case: **EKS**
   - Select **EKS - Cluster**
   - Click **Next**
3. **Add permissions** (automatically selected):
   - `AmazonEKSClusterPolicy`
   - Click **Next**
4. **Name, review, and create**:
   - Role name: `eksClusterRole`
   - Description: "Allows EKS to manage clusters on your behalf"
   - Click **Create role**

### 1.2 Create EKS Node Group IAM Role with Consolidated Permissions

Since we're not using IRSA, all pod permissions will be granted through the node group IAM role.

#### First, create custom policies for pod permissions:

**Policy 1: Aurora Logs Base Permissions**

1. Navigate to **IAM Console** → **Policies** → **Create policy**
2. Choose **JSON** and paste:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RDSAccess",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBClusters",
        "rds:DescribeDBInstances",
        "rds:DescribeDBLogFiles",
        "rds:ListTagsForResource",
        "rds:DownloadDBLogFilePortion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/aurora-instance-metadata",
        "arn:aws:dynamodb:*:*:table/aurora-instance-metadata/index/*",
        "arn:aws:dynamodb:*:*:table/aurora-log-file-tracking",
        "arn:aws:dynamodb:*:*:table/aurora-log-file-tracking/index/*",
        "arn:aws:dynamodb:*:*:table/aurora-log-processing-jobs",
        "arn:aws:dynamodb:*:*:table/aurora-log-processing-jobs/index/*"
      ]
    },
    {
      "Sid": "ElastiCacheAccess",
      "Effect": "Allow",
      "Action": [
        "elasticache:DescribeCacheClusters",
        "elasticache:DescribeReplicationGroups"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3Access",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucketMultipartUploads"
      ],
      "Resource": [
        "arn:aws:s3:::company-aurora-logs-poc",
        "arn:aws:s3:::company-aurora-logs-poc/*",
        "arn:aws:s3:::company-k8s-logs-poc",
        "arn:aws:s3:::company-k8s-logs-poc/*"
      ]
    },
    {
      "Sid": "EC2Access",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces"
      ],
      "Resource": "*"
    }
  ]
}
```
3. **Review and create**:
   - Policy name: `eks-aurora-logs-policy`
   - Description: "Permissions for Aurora logs processing pods on EKS nodes - RDS API access and S3 storage"
   - Click **Create policy**

#### Create the Node Group Role:

1. Navigate to **IAM Console** → **Roles** → **Create role**
2. **Select trusted entity**:
   - Trusted entity type: **AWS service**
   - Use case: **EC2**
   - Click **Next**
3. **Add permissions** - search and attach these policies:
   - `AmazonEKSWorkerNodePolicy`
   - `AmazonEKS_CNI_Policy`
   - `AmazonEC2ContainerRegistryReadOnly`
   - `AmazonSSMManagedInstanceCore`
   - `eks-aurora-logs-policy` (the custom policy you just created)
   - Click **Next**
4. **Name, review, and create**:
   - Role name: `eksNodeGroupRole`
   - Description: "Allows EC2 instances in EKS node group to call AWS services and run Aurora logs processing workloads"
   - Click **Create role**

### 1.3 Create jenkins-ecr-user

create jenkins-ecr-push-policy and attach it to jenkins-ecr-user user

3. **Set permissions** → **Attach policies directly** → **Create policy** → **JSON**:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:CompleteLayerUpload",
                "ecr:InitiateLayerUpload",
                "ecr:PutImage",
                "ecr:UploadLayerPart",
                "ecr:BatchDeleteImage",
                "ecr:ListImages",
                "ecr:DescribeRepositories",
                "ecr:CreateRepository",
                "ecr:GetRepositoryPolicy",
                "ecr:SetRepositoryPolicy",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            "Resource": [
                "arn:aws:ecr:us-east-1:072006186126:repository/aurora-log-system",
                "arn:aws:ecr:us-east-1:072006186126:repository/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "ecr:GetAuthorizationToken",
            "Resource": "*"
        }
    ]
}
```
now create secret key and access key 

and pass them in sudo -u jenkins aws configure

## Step 2: Create Security Groups

Navigate to **EC2 Console** → **Security Groups** → **Create security group** for each:

### 2.1 Security Group Configurations

| Security Group | POC Rules | Production Rules | Notes |
|----------------|-----------|------------------|-------|
| **eks-node-sg** | All traffic from self + control plane | Restricted ports only | POC allows easier debugging |
| **eks-control-plane-sg** | HTTPS from nodes | Same | Essential for cluster operation |
| **kafka-pod-sg** | 9092-9093 from nodes | Same + internal only | Kafka ports required |
| **valkey-cluster-sg** | 6379 from nodes | Same | Redis protocol |
| **aurora-mysql-sg** | 3306 from all (0.0.0.0/0) | 3306 from nodes only | POC allows direct testing |
| **openobserve-sg** | 5080 from ALB + nodes | Same | Web UI access |
| **alb-sg** | 80/443 from all | Same + WAF | Public access needed |

### 2.2 EKS Node Security Group

- **Security group name**: `eks-node-sg`
- **Description**: Security group for EKS worker nodes
- **VPC**: Select your VPC [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| All traffic | All | eks-node-sg | Node to node communication |
| HTTPS | 443 | eks-control-plane-sg | API server to kubelet |
| Custom TCP | 10250 | eks-control-plane-sg | API server to kubelet |
| Custom TCP | 53 | eks-node-sg | DNS |
| Custom UDP | 53 | eks-node-sg | DNS |

**Outbound Rules**: Leave default (All traffic to 0.0.0.0/0)

### 2.3 EKS Control Plane Security Group

- **Security group name**: `eks-control-plane-sg`
- **Description**: Security group for EKS control plane
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| HTTPS | 443 | eks-node-sg | Node to API server |

**Outbound Rules**: Leave default

### 2.4 Kafka Pod Security Group

- **Security group name**: `kafka-pod-sg`
- **Description**: Security group for Kafka pods
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 9092 | eks-node-sg | Kafka client connections |
| Custom TCP | 9093 | kafka-pod-sg | KRaft controller port |
| All traffic | All | kafka-pod-sg | Inter-broker communication |

### 2.5 Valkey Cluster Security Group

- **Security group name**: `valkey-cluster-sg`
- **Description**: Security group for Valkey cache cluster
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 6379 | eks-node-sg | Redis protocol access |

### 2.6 Aurora MySQL Security Group

- **Security group name**: `aurora-mysql-sg`
- **Description**: Security group for Aurora MySQL cluster
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| MYSQL/Aurora | 3306 | eks-node-sg | Access from EKS |
| MYSQL/Aurora | 3306 | 0.0.0.0/0 | Direct access for testing |

### 2.7 OpenObserve Security Group

- **Security group name**: `openobserve-sg`
- **Description**: Security group for OpenObserve pods
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 5080 | alb-sg | HTTP from ALB |
| Custom TCP | 5080 | eks-node-sg | Health checks |

### 2.8 Application Load Balancer Security Group

- **Security group name**: `alb-sg`
- **Description**: Security group for ALB fronting OpenObserve
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port Range | Source | Description |
|------|------|--------|-------------|
| HTTPS | 443 | 0.0.0.0/0 | Public HTTPS access |
| HTTP | 80 | 0.0.0.0/0 | Public HTTP (redirect) |

**Outbound Rules**:
| Type | Port Range | Destination | Description |
|------|------|--------|-------------|
| Custom TCP | 5080 | openobserve-sg | To OpenObserve |

## Step 3: Create S3 Bucket

### 3.1 S3 Bucket Configuration

| Setting | POC Configuration | Production Configuration |
|---------|------------------|-------------------------|
| **Bucket Name** | company-aurora-logs-poc | company-aurora-logs-prod |
| **Versioning** | Enabled | Enabled |
| **Encryption** | SSE-S3 | SSE-KMS with CMK |
| **Replication** | None | Cross-region |
| **Lifecycle** | 30 days to Glacier | Intelligent-Tiering |
| **Access Logging** | Disabled | Enabled |
| **Object Lock** | Disabled | Enabled for compliance |

1. Navigate to **S3 Console** → **Create bucket**
2. **General configuration**:
   - Bucket name: `company-aurora-logs-poc`
   - AWS Region: [region]
3. **Object Ownership**:
   - Select **ACLs disabled (recommended)**
4. **Block Public Access settings**:
   - Keep all checkboxes checked (Block all public access)
5. **Bucket Versioning**:
   - Select **Enable**
6. **Default encryption**:
   - Encryption type: **Server-side encryption with Amazon S3 managed keys (SSE-S3)**
   - Bucket Key: **Enable**
7. Click **Create bucket**

### 3.2 Create Folder Structure

After bucket creation:
1. Click on the bucket name
2. Click **Create folder** for each:
   - Folder name: `slowquery`
   - Folder name: `error`

### 3.3 Create K8s Logs Bucket

Repeat the above steps to create a second bucket for Kubernetes logs:
1. Navigate to **S3 Console** → **Create bucket**
2. **General configuration**:
   - Bucket name: `company-k8s-logs-poc`
   - AWS Region: [region]
3. Use same settings as aurora-logs bucket
4. After creation, create folder:
   - Folder name: `cluster-logs`