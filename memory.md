# Code Modification Restrictions

## Important: Read This Before Making Any Changes

### Restricted Components - DO NOT MODIFY WITHOUT EXPLICIT PERMISSION

The following components are **LOCKED** and must not be modified without explicit user permission:

1. **Discovery Service** (`/discovery/*`)
   - All files in the discovery directory
   - Including main.go, main_test.go, Dockerfile, go.mod

2. **Processor Service** (`/processor/*`)
   - All files in the processor directory
   - Including main.go, main_test.go, Dockerfile, go.mod

3. **OpenObserve** (`/openobserve/*`)
   - All files in the openobserve directory
   - Including Dockerfile and configuration files

4. **Kafka** (`/kafka/*`)
   - All files in the kafka directory
   - Including Dockerfile and configuration files

5. **Jenkins Pipeline** (`/Jenkinsfile`)
   - The entire Jenkins pipeline configuration
   - No modifications to build, test, or deployment stages

### Required Action Before Any Changes

1. **ALWAYS** read this memory.md file first before making any code changes
2. If a change involves any of the restricted components above, **ASK FOR PERMISSION** from the user
3. Clearly explain what changes are needed and why
4. Wait for explicit approval before proceeding

### Reason for Restrictions

These components have been thoroughly tested, optimized, and are currently working in production. Any unauthorized changes could disrupt the live system.

### Infrastructure Deployment Restrictions

**IMPORTANT**: Do NOT run `terraform apply` or any infrastructure deployment commands without explicit user permission. Always:
1. Check existing infrastructure using AWS CLI first
2. Compare with the planned changes
3. Report what exists and what needs to be created/modified
4. Wait for user approval before applying any changes

### Existing S3 Buckets

- **Aurora Logs Bucket**: `company-aurora-logs-poc` (already exists - use this instead of creating new one)

### Terraform Destroy Restrictions

When running `terraform destroy`, the following resources must NOT be deleted:
- VPC and Subnets
- Security Groups
- IAM Roles and Users
- RDS Subnet Group
- ECR Repository
- EKS Cluster
- S3 Buckets (must be emptied but not deleted)
- DynamoDB tables (must be emptied but not deleted - data can be cleared)

Only the following can be destroyed:
- EKS Node Groups
- RDS Aurora Cluster Instances (but not subnet group)
- Kubernetes namespace
- S3 k8s-logs bucket (has force_destroy=true)

Note: ElastiCache Valkey Cluster now has prevent_destroy lifecycle rule and will NOT be deleted during terraform destroy

### IAM Trust Relationship Issue (RESOLVED)

**Issue**: Both ECS and EKS instances not registering with their clusters
**Root Cause**: IAM trust relationship JSON format issues

**Problem Identified**: The trust relationship JSON had formatting issues that weren't visible in AWS CLI output
- The JSON appeared correct when queried but had hidden formatting problems
- This prevented EC2 instances from assuming the role and registering with EKS cluster

**Current Trust Relationships (FIXED):**
- EKS Cluster Role (eksClusterRole): Trusts eks.amazonaws.com
- EKS Node Role (eksNodeGroupRole): Trusts ec2.amazonaws.com

**Common Issues to Check**:
1. Invalid JSON formatting (extra commas, missing quotes)
2. Array vs string format for Service principal
3. Hidden characters or encoding issues (UTF-8 BOM)
4. Incorrect Action format

**Resolution**: User manually fixed the trust relationship JSON format
**Status**: Trust relationships now working correctly

### ECS Resource Configuration (DO NOT CHANGE)

**EC2 Instance Type**: t4g.medium (ARM64)
- **vCPUs**: 2 (2048 CPU units in ECS)
- **Memory**: 4 GB (4096 MB)
- **Available for containers**: ~3835 MB (after ECS agent overhead)

**Service Resource Allocation** (Each service runs on its own dedicated t4g.medium instance):

| Service      | CPU Units | Memory (MB) | Notes                                           |
|--------------|-----------|-------------|-------------------------------------------------|
| Discovery    | 2048      | 3584        | Full capacity of t4g.medium                     |
| Processor    | 2048      | 3584        | Full capacity of t4g.medium                     |
| Kafka        | 2048      | 3584        | Full capacity of t4g.medium                     |
| OpenObserve  | 2048      | 3584        | Full capacity of t4g.medium                     |

**Important**:
- Each service gets its own dedicated t4g.medium instance (4 instances total)
- Memory is set to 3584 MB to leave overhead for ECS agent (~251 MB)
- CPU is set to full 2048 units (2 vCPUs)
- **DO NOT MODIFY THESE VALUES** - They are optimized for t4g.medium instances

### Last Updated

- Date: 2025-08-01
- Reason: Added ECS resource configuration for t4g.medium instances
- Status: All restricted components are stable and functional