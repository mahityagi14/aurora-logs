variable "bucket_names" {
  description = "S3 bucket names"
  type = object({
    aurora_logs = string
    k8s_logs    = string
  })
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "log_retention_days" {
  description = "Number of days to retain logs in S3"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}