variable "table_names" {
  description = "DynamoDB table names"
  type = object({
    instance_metadata = string
    tracking         = string
    jobs            = string
  })
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}