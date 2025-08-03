# AWS Configuration
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (poc or production)"
  type        = string
  validation {
    condition     = contains(["poc", "production"], var.environment)
    error_message = "Environment must be either 'poc' or 'production'."
  }
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "aurora-logs"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# VPC Configuration (for reference - using existing VPC)
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 3
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
}

# Security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access EKS API (production only)"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Update this for production
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Note: Kubernetes deployment variables are defined in k8s-*.tf files
# to keep them close to their usage

# Application Configuration
variable "kafka_retention_hours" {
  description = "Kafka log retention in hours"
  type        = number
  default     = 24
}

variable "openobserve_retention_days" {
  description = "OpenObserve data retention in days"
  type        = number
  default     = 30
}

variable "processor_max_batch_size" {
  description = "Maximum batch size for processor"
  type        = number
  default     = 100
}

variable "discovery_interval_seconds" {
  description = "Discovery interval in seconds"
  type        = number
  default     = 300
}

# Resource Sizing
variable "kafka_storage_size" {
  description = "Kafka PVC storage size"
  type        = string
  default     = "5Gi"
}

variable "openobserve_storage_size" {
  description = "OpenObserve PVC storage size"
  type        = string
  default     = "10Gi"
}

# High Availability
variable "kafka_replicas" {
  description = "Number of Kafka replicas (1 for POC, 3 for production)"
  type        = number
  default     = 1
}

variable "openobserve_replicas" {
  description = "Number of OpenObserve replicas"
  type        = number
  default     = 1
}

variable "discovery_replicas" {
  description = "Number of Discovery replicas"
  type        = number
  default     = 1
}

# Image Configuration
variable "image_pull_policy" {
  description = "Image pull policy for containers"
  type        = string
  default     = "Always"
}

variable "image_registry" {
  description = "Container image registry"
  type        = string
  default     = ""
}

# Feature Flags
variable "enable_profiling" {
  description = "Enable application profiling"
  type        = bool
  default     = false
}

variable "enable_caching" {
  description = "Enable caching features"
  type        = bool
  default     = true
}

variable "enable_compression" {
  description = "Enable compression for data transfer"
  type        = bool
  default     = true
}

# Credentials (should be provided via terraform.tfvars or environment variables)
variable "openobserve_admin_email" {
  description = "OpenObserve admin email"
  type        = string
  default     = "admin@example.com"
  sensitive   = true
}

variable "openobserve_admin_password" {
  description = "OpenObserve admin password"
  type        = string
  default     = "Complexpass#123"
  sensitive   = true
}