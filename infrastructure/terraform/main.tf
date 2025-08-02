# This configuration uses existing AWS resources instead of creating new ones

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
    k8s_logs    = "aurora-k8s-logs-${data.aws_caller_identity.current.account_id}"  # Unique name to avoid conflict
  }
}

# Data sources
data "aws_caller_identity" "current" {}

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

# Import existing EKS cluster
data "aws_eks_cluster" "existing" {
  name = "aurora-logs-poc-cluster"
}

data "aws_eks_cluster_auth" "existing" {
  name = "aurora-logs-poc-cluster"
}

# Import existing RDS cluster
data "aws_rds_cluster" "existing" {
  cluster_identifier = "aurora-mysql-poc-01"
}

# Import existing security groups
data "aws_security_group" "eks_cluster" {
  id = "sg-0c67e6b50814f89df"
}

data "aws_security_group" "eks_node" {
  id = "sg-052a7b718e534fed9"
}

data "aws_security_group" "rds" {
  id = "sg-0781a0b7315baf1ab"
}

data "aws_security_group" "openobserve" {
  id = "sg-00bacfeb03f17d36c"
}

data "aws_security_group" "kafka" {
  id = "sg-026743f9ff9eb9c4f"
}

# Valkey security group will be created by the elasticache module
# data "aws_security_group" "valkey" {
#   id = "sg-0cab79d149c7930f5"
# }

# Import existing IAM roles
data "aws_iam_role" "eks_cluster" {
  name = "eksClusterRole"
}

data "aws_iam_role" "eks_node" {
  name = "eksNodeGroupRole"
}

data "aws_iam_user" "jenkins_ecr" {
  user_name = "jenkins-ecr-user"
}

# Create only the missing resources

# COMMENTED OUT - Using existing resources
# S3 buckets - aurora-logs bucket already exists as "company-aurora-logs-poc"
# K8s logs bucket is created in k8s-logs-bucket.tf file
# module "s3" {
#   source = "./modules/s3"
#   bucket_names = local.s3_buckets
#   environment  = var.environment
#   log_retention_days = var.environment == "production" ? 365 : 30
#   tags = local.common_tags
# }

# COMMENTED OUT - DynamoDB tables already exist
# Tables exist: aurora-instance-metadata, aurora-log-file-tracking, aurora-log-processing-jobs
# module "dynamodb" {
#   source = "./modules/dynamodb"
#   table_names = local.dynamodb_tables
#   environment = var.environment
#   tags = local.common_tags
# }

# COMMENTED OUT - ECR repository already exists as "aurora-log-system"
# module "ecr" {
#   source = "./modules/ecr"
#   repository_name = "aurora-log-system"
#   environment     = var.environment
#   push_principal_arns = [data.aws_iam_user.jenkins_ecr.arn]
#   pull_principal_arns = [data.aws_iam_role.eks_node.arn]
#   additional_repositories = []
#   tags = local.common_tags
# }

# ElastiCache Valkey cluster (since you don't have one)
module "elasticache" {
  source = "./modules/elasticache"
  
  name_prefix            = var.name_prefix
  environment            = var.environment
  vpc_id                 = data.aws_vpc.existing.id
  private_subnet_ids     = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
  eks_security_group_ids = [data.aws_security_group.eks_node.id]
  
  cache_config = {
    cluster_id      = "${var.name_prefix}-valkey"
    engine_version  = "8.0"  # Using Valkey version 8 (latest)
    node_type       = "cache.t4g.micro"  # Minimal for POC
    num_cache_nodes = 1
    auth_token      = ""  # No auth for POC
  }
  
  sns_topic_arn = null  # No SNS topic for POC
  
  tags = local.common_tags
}

# Provider configuration for Kubernetes
provider "kubernetes" {
  host                   = data.aws_eks_cluster.existing.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.existing.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.existing.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.existing.token
  }
}

# Create namespace - Commented out due to authentication issue
# resource "kubernetes_namespace" "aurora_logs" {
#   metadata {
#     name = "aurora-logs"
#   }
# }

# Output values for use in K8s deployment
output "vpc_id" {
  value = data.aws_vpc.existing.id
}

output "eks_cluster_name" {
  value = data.aws_eks_cluster.existing.name
}

output "rds_endpoint" {
  value = data.aws_rds_cluster.existing.endpoint
}

output "elasticache_endpoint" {
  value = module.elasticache.primary_endpoint_address
}

output "s3_aurora_logs_bucket" {
  value = data.aws_s3_bucket.existing_aurora_logs.id
}

output "s3_k8s_logs_bucket" {
  value = aws_s3_bucket.k8s_logs.id
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

# Configure kubectl
output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${data.aws_eks_cluster.existing.name}"
}