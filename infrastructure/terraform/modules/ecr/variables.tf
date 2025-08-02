variable "repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "aurora-log-system"
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  type        = string
  default     = "MUTABLE"
}

variable "enable_image_scanning" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "The encryption type to use for the repository"
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key to use for encryption"
  type        = string
  default     = null
}

variable "untagged_image_retention_days" {
  description = "Number of days to retain untagged images"
  type        = number
  default     = 7
}

variable "dev_image_retention_days" {
  description = "Number of days to retain development images"
  type        = number
  default     = 30
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain"
  type        = number
  default     = 50
}

variable "pull_principal_arns" {
  description = "List of IAM principal ARNs that can pull images"
  type        = list(string)
  default     = []
}

variable "push_principal_arns" {
  description = "List of IAM principal ARNs that can push images"
  type        = list(string)
  default     = []
}

variable "repository_size_alarm_threshold" {
  description = "Repository size threshold in bytes for CloudWatch alarm"
  type        = number
  default     = 10737418240  # 10 GB
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs for CloudWatch alarms"
  type        = list(string)
  default     = []
}

variable "additional_repositories" {
  description = "List of additional ECR repositories to create"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}