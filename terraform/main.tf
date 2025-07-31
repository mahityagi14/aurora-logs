# ECS-based configuration for Aurora Log System
# Uses existing AWS resources and replaces EKS with ECS

locals {
  name_prefix = var.name_prefix
  
  common_tags = {
    Project     = "aurora-log-system"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
    CreatedAt   = timestamp()
  }

  # DynamoDB table names - using existing tables
  dynamodb_tables = {
    instance_metadata = "aurora-instance-metadata"  # Existing table
    tracking         = "aurora-log-file-tracking"  # Existing table
    jobs            = "aurora-log-processing-jobs"  # Existing table
  }

  # S3 bucket names
  s3_buckets = {
    aurora_logs = "company-aurora-logs-poc"  # Using existing bucket
    k8s_logs    = "aurora-k8s-logs-072006186126"  # Reuse for ECS logs
  }
  
  # Container configurations - Using full t4g.medium capacity (2 vCPUs, 4GB RAM)
  container_configs = {
    discovery = {
      name   = "discovery"
      image  = "${data.aws_ecr_repository.existing_aurora_log_system.repository_url}:discovery-latest"
      cpu    = 1792  # 1.75 vCPUs
      memory = 3584  # 3.5 GB (leaving some memory for ECS agent)
      count  = var.environment == "production" ? 2 : 1
    }
    processor = {
      name   = "processor"
      image  = "${data.aws_ecr_repository.existing_aurora_log_system.repository_url}:processor-latest"
      cpu    = 1792  # 1.75 vCPUs
      memory = 3584  # 3.5 GB (leaving some memory for ECS agent)
      count  = var.environment == "production" ? 2 : 1
    }
    kafka = {
      name   = "kafka"
      image  = "${data.aws_ecr_repository.existing_aurora_log_system.repository_url}:kafka-latest"
      cpu    = 1792  # 1.75 vCPUs
      memory = 3584  # 3.5 GB (leaving some memory for ECS agent)
      count  = 1
    }
    openobserve = {
      name   = "openobserve"
      image  = "public.ecr.aws/zinclabs/openobserve:v0.15.0-rc4"
      cpu    = 1792  # 1.75 vCPUs
      memory = 3584  # 3.5 GB (leaving some memory for ECS agent)
      count  = 1
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Import existing VPC
data "aws_vpc" "existing" {
  id = "vpc-0709b8bef0bf79401"
}

# Import existing subnets
data "aws_subnet" "public_1" {
  id = "subnet-09a05d3f60260977d"
}

data "aws_subnet" "public_2" {
  id = "subnet-02be44306a0c4a66f"
}

data "aws_subnet" "private_1" {
  id = "subnet-065f0d4951fc12ef9"
}

data "aws_subnet" "private_2" {
  id = "subnet-0726157ced0ebe2cf"
}

# Import existing RDS cluster
data "aws_rds_cluster" "existing" {
  cluster_identifier = "aurora-mysql-poc-01"
}

# Import existing security groups
data "aws_security_group" "rds" {
  id = "sg-0781a0b7315baf1ab"
}

data "aws_security_group" "openobserve" {
  id = "sg-00bacfeb03f17d36c"
}

data "aws_security_group" "kafka" {
  id = "sg-026743f9ff9eb9c4f"
}

# Create consolidated ECS task execution role as per ecs-phases
resource "aws_iam_role" "ecs_task_execution" {
  name = "aurora-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Create custom execution policy as per ecs-phases
resource "aws_iam_policy" "ecs_execution_policy" {
  name        = "aurora-ecs-execution-policy"
  description = "Consolidated execution policy for Aurora ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "arn:aws:ecr:*:*:repository/aurora-log-system"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach custom policy to execution role
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_execution_policy.arn
}

data "aws_iam_user" "jenkins_ecr" {
  user_name = "jenkins-ecr-user"
}

# Import existing DynamoDB tables
data "aws_dynamodb_table" "existing_metadata" {
  name = local.dynamodb_tables.instance_metadata
}

data "aws_dynamodb_table" "existing_tracking" {
  name = local.dynamodb_tables.tracking
}

data "aws_dynamodb_table" "existing_jobs" {
  name = local.dynamodb_tables.jobs
}

# Import existing S3 bucket
data "aws_s3_bucket" "existing_aurora_logs" {
  bucket = local.s3_buckets.aurora_logs
}

# Import existing ECR repository
data "aws_ecr_repository" "existing_aurora_log_system" {
  name = "aurora-log-system"
}

# Use existing ECS Cluster
data "aws_ecs_cluster" "aurora_logs" {
  cluster_name = "gifted-hippopotamus-lcq6xe"
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.name_prefix}-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = data.aws_vpc.existing.id

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow internal communication
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-ecs-tasks-sg"
    }
  )
}

# Create consolidated IAM role for ECS tasks as per ecs-phases
resource "aws_iam_role" "ecs_task_role" {
  name = "aurora-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

# Create comprehensive task policy as per ecs-phases
resource "aws_iam_policy" "ecs_task_policy" {
  name        = "aurora-ecs-task-policy"
  description = "Consolidated task policy for all Aurora ECS services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "RDSAccess"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBClusters",
          "rds:DescribeDBInstances",
          "rds:DescribeDBLogFiles",
          "rds:DownloadDBLogFilePortion",
          "rds:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid = "DynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:BatchWriteItem",
          "dynamodb:DescribeTable"
        ]
        Resource = [
          "arn:aws:dynamodb:*:*:table/aurora-instance-metadata",
          "arn:aws:dynamodb:*:*:table/aurora-log-file-tracking",
          "arn:aws:dynamodb:*:*:table/aurora-log-processing-jobs"
        ]
      },
      {
        Sid = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads"
        ]
        Resource = [
          "arn:aws:s3:::company-aurora-logs-poc",
          "arn:aws:s3:::company-aurora-logs-poc/*"
        ]
      },
      {
        Sid = "ElastiCacheAccess"
        Effect = "Allow"
        Action = [
          "elasticache:DescribeCacheClusters",
          "elasticache:DescribeReplicationGroups"
        ]
        Resource = "*"
      },
      {
        Sid = "EC2Access"
        Effect = "Allow"
        Action = [
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid = "ECSAccess"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Sid = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "AuroraLogProcessor/POC"
          }
        }
      }
    ]
  })
}

# Attach comprehensive policy to task role
resource "aws_iam_role_policy_attachment" "ecs_task_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.name_prefix}"
  retention_in_days = var.environment == "production" ? 30 : 7

  tags = local.common_tags
}

# Import existing Valkey/ElastiCache
data "aws_elasticache_replication_group" "existing_valkey" {
  replication_group_id = "aurora-logs-poc-valkey"
}

# Output values
output "ecs_cluster_name" {
  value = data.aws_ecs_cluster.aurora_logs.cluster_name
}

output "ecs_cluster_arn" {
  value = data.aws_ecs_cluster.aurora_logs.arn
}

output "vpc_id" {
  value = data.aws_vpc.existing.id
}

output "private_subnet_ids" {
  value = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
}

output "public_subnet_ids" {
  value = [data.aws_subnet.public_1.id, data.aws_subnet.public_2.id]
}

output "rds_endpoint" {
  value = data.aws_rds_cluster.existing.endpoint
}

output "elasticache_endpoint" {
  value = data.aws_elasticache_replication_group.existing_valkey.primary_endpoint_address
}

output "s3_aurora_logs_bucket" {
  value = data.aws_s3_bucket.existing_aurora_logs.id
}

output "s3_ecs_logs_bucket" {
  value = local.s3_buckets.k8s_logs
}

output "dynamodb_tables" {
  value = {
    instance_metadata = data.aws_dynamodb_table.existing_metadata.name
    tracking         = data.aws_dynamodb_table.existing_tracking.name
    jobs            = data.aws_dynamodb_table.existing_jobs.name
  }
}

output "ecr_repository_url" {
  value = data.aws_ecr_repository.existing_aurora_log_system.repository_url
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task_role.arn
}

output "ecs_security_group_id" {
  value = aws_security_group.ecs_tasks.id
}