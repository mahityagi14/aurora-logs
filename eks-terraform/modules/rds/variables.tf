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
  description = "List of private subnet IDs for RDS"
  type        = list(string)
}

variable "eks_security_group_ids" {
  description = "Security group IDs for EKS nodes that need access to RDS"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones for the cluster"
  type        = list(string)
}

variable "cluster_config" {
  description = "Aurora cluster configuration"
  type = object({
    cluster_identifier = string
    engine_version     = string
    instance_class     = string
    instance_count     = number
    database_name      = string
    master_username    = string
    master_password    = string
  })

  sensitive = true
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}