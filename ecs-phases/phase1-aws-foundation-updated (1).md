# Phase 1: AWS Foundation Setup - Updated Console Guide

## Overview
This guide walks through setting up the foundation AWS infrastructure for the Aurora MySQL Log Processing POC using Apache Kafka 4.0 on ECS. All steps are performed through the AWS Management Console.

**Key Features:**
- Uses public subnets for simplified POC deployment
- Proper ECS instance profile configuration
- CloudWatch Container Insights enabled
- Consistent variable placeholders across all phases

## Prerequisites
- AWS Account with appropriate permissions
- Existing VPC with at least 3 public subnets
- Access to AWS Management Console
- Note your AWS region and account ID

## Step 1: Create IAM Roles and Policies

### 1.1 Create ECS Instance Profile and Role

**CRITICAL:** This role allows EC2 instances to function as ECS container instances.

#### Create the Role:
1. Navigate to **IAM Console** → **Roles** → **Create role**
2. **Select trusted entity**:
   - Choose **AWS service**
   - Use case: **EC2**
   - Click **Next**
3. **Add permissions** (search and attach these policies):
   - `AmazonEC2ContainerServiceforEC2Role`
   - `CloudWatchAgentServerPolicy`
   - `AmazonSSMManagedInstanceCore`
   - Click **Next**
4. **Name, review, and create**:
   - Role name: `ecsInstanceRole`
   - Description: "Allows EC2 instances in ECS cluster to call AWS services"
   - Click **Create role**

#### Verify Instance Profile:
The instance profile should be created automatically with the role. To verify:
1. Go to the created role `ecsInstanceRole`
2. Check that "Instance profile ARN" is shown in the summary
3. If missing, create it manually via CLI:
```bash
aws iam create-instance-profile --instance-profile-name ecsInstanceRole
aws iam add-role-to-instance-profile --instance-profile-name ecsInstanceRole --role-name ecsInstanceRole
```

### 1.2 Create Consolidated ECS Task Execution Role

#### Create Execution Role Policy:
1. **IAM Console** → **Policies** → **Create policy** → **JSON**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "arn:aws:ecr:*:*:repository/aurora-log-system"
    }
  ]
}
```
2. Policy name: `aurora-ecs-execution-policy`
3. Click **Create policy**

#### Create Execution Role:
1. **IAM Console** → **Roles** → **Create role**
2. **Select trusted entity**:
   - Choose **AWS service**
   - Use case: **Elastic Container Service** → **Elastic Container Service Task**
   - Click **Next**
3. **Add permissions**:
   - `aurora-ecs-execution-policy`
   - Click **Next**
4. **Name, review, and create**:
   - Role name: `aurora-ecs-execution-role`
   - Description: "Consolidated execution role for all Aurora ECS tasks"
   - Click **Create role**

### 1.3 Create Consolidated Task Role

**Note**: For production environments, it's recommended to use separate task roles for each service following the principle of least privilege. This consolidated approach is suitable for POC/development.

#### Create Comprehensive Task Policy:
1. **Create policy** - IAM Console → **Policies** → **Create policy** → **JSON**:
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
        "rds:DownloadDBLogFilePortion",
        "rds:ListTagsForResource"
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
        "arn:aws:dynamodb:*:*:table/aurora-log-file-tracking",
        "arn:aws:dynamodb:*:*:table/aurora-log-processing-jobs"
      ]
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
        "arn:aws:s3:::company-aurora-logs-poc/*"
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
      "Sid": "EC2Access",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSAccess",
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeServices",
        "ecs:UpdateService"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "AuroraLogProcessor/POC"
        }
      }
    }
  ]
}
```
2. Policy name: `aurora-ecs-task-policy`
3. Create the role:
   - Trusted entity: **Elastic Container Service Task**
   - Attach the policy: `aurora-ecs-task-policy`
   - Role name: `aurora-ecs-task-role`
   - Description: "Consolidated task role for all Aurora ECS services"

## Alternative: Using Individual Service Roles (Optional)

For production environments where stricter security isolation is required, you can create individual execution and task roles for each service. This follows the principle of least privilege where each service only has the permissions it needs.

To use individual roles:
1. Create separate execution roles for each service (discovery, processor, kafka, openobserve)
2. Create separate task roles with only the required permissions for each service
3. Update the task definitions in Phase 4 to use the specific roles

Benefits of individual roles:
- Better security isolation
- Easier to audit permissions per service
- Reduced blast radius if a service is compromised
- More granular control over permissions

The consolidated approach shown above is suitable for POC/development environments where simplicity is preferred.

## Step 2: Create Security Groups

Navigate to **EC2 Console** → **Security Groups** → **Create security group** for each:

### 2.1 ECS Container Instances Security Group

- **Name**: `ecs-instances-sg`
- **Description**: Security group for ECS container instances
- **VPC**: Select your VPC [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| SSH | 22 | 0.0.0.0/0 | SSH access (restrict in prod) |
| All traffic | All | ecs-instances-sg | Inter-instance communication |

**Outbound Rules**: Leave default (All traffic to 0.0.0.0/0)

### 2.2 Kafka Brokers Security Group

- **Name**: `kafka-brokers-sg`
- **Description**: Security group for Kafka brokers on ECS
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 9092 | ecs-instances-sg | Kafka client connections |
| Custom TCP | 9093 | kafka-brokers-sg | KRaft controller port |
| All traffic | All | kafka-brokers-sg | Inter-broker communication |

### 2.3 Valkey Cluster Security Group

- **Name**: `valkey-cluster-sg`
- **Description**: Security group for Valkey cache cluster
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 6379 | ecs-instances-sg | Redis protocol access |

### 2.4 Aurora MySQL Security Group

- **Name**: `aurora-mysql-sg`
- **Description**: Security group for Aurora MySQL cluster
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| MYSQL/Aurora | 3306 | ecs-instances-sg | Access from ECS |
| MYSQL/Aurora | 3306 | 0.0.0.0/0 | Direct access for testing |

### 2.5 OpenObserve Security Group

- **Name**: `openobserve-sg`
- **Description**: Security group for OpenObserve on ECS
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| Custom TCP | 5080 | alb-sg | HTTP from ALB |
| Custom TCP | 5080 | ecs-instances-sg | Health checks |

### 2.6 Application Load Balancer Security Group

- **Name**: `alb-sg`
- **Description**: Security group for ALB fronting OpenObserve
- **VPC**: [vpc-id]

**Inbound Rules**:
| Type | Port | Source | Description |
|------|------|--------|-------------|
| HTTPS | 443 | 0.0.0.0/0 | Public HTTPS access |
| HTTP | 80 | 0.0.0.0/0 | Public HTTP (redirect) |

**Outbound Rules**:
| Type | Port | Destination | Description |
|------|------|-------------|-------------|
| Custom TCP | 5080 | openobserve-sg | To OpenObserve |

## Step 3: Create S3 Bucket

1. Navigate to **S3 Console** → **Create bucket**
2. **General configuration**:
   - Bucket name: `company-aurora-logs-poc`
   - AWS Region: [region]
3. **Object Ownership**:
   - Select **ACLs disabled (recommended)**
4. **Block Public Access settings**:
   - ✓ Block all public access (keep all checkboxes checked)
5. **Bucket Versioning**:
   - Select **Enable**
6. **Default encryption**:
   - Encryption type: **Server-side encryption with Amazon S3 managed keys (SSE-S3)**
   - Bucket Key: **Enable**
7. **Advanced settings**:
   - Object Lock: **Disable**
8. Click **Create bucket**

### 3.1 Create Folder Structure

After bucket creation:
1. Click on the bucket name
2. Click **Create folder** for each:
   - Folder name: `slowquery`
   - Folder name: `error`

Final structure:
```
company-aurora-logs-poc/
├── slowquery/
└── error/
```

## Summary of Created Resources

After completing Phase 1, you should have:

### IAM Resources (Simplified for POC):
- 1 ECS Instance Profile: `ecsInstanceRole`
- 1 Execution Role: `aurora-ecs-execution-role` (shared by all services)
- 1 Task Role: `aurora-ecs-task-role` (shared by all services)
- 2 Policies: `aurora-ecs-execution-policy` and `aurora-ecs-task-policy`

Note: This consolidated IAM approach simplifies the POC setup. For production, consider using individual roles per service for better security isolation.

### Security Groups:
- 6 Security Groups configured for each component

### S3:
- 1 S3 bucket: `company-aurora-logs-poc` with folder structure

## Next Steps
Proceed to Phase 2 to set up the database infrastructure including Aurora MySQL, DynamoDB tables, Valkey cache, and ECR repository.