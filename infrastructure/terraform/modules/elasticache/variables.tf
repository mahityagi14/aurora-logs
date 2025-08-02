variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ElastiCache"
  type        = list(string)
}

variable "eks_security_group_ids" {
  description = "Security group IDs for EKS nodes that need access to cache"
  type        = list(string)
}

variable "cache_config" {
  description = "ElastiCache configuration"
  type = object({
    cluster_id      = string
    engine_version  = string
    node_type       = string
    num_cache_nodes = number
    auth_token      = string  # Required for production
  })
  sensitive = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for ElastiCache notifications"
  type        = string
  default     = null
}

variable "sns_alarm_topic_arns" {
  description = "List of SNS topic ARNs for CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}