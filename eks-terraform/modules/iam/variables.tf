variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "s3_bucket_names" {
  description = "S3 bucket names"
  type = object({
    aurora_logs = string
    k8s_logs    = string
  })
}

variable "dynamodb_tables" {
  description = "DynamoDB table names"
  type = object({
    instance_metadata = string
    tracking         = string
    jobs            = string
  })
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}