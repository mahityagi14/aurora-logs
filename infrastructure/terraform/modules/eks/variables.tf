variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "List of subnet IDs for the EKS node groups"
  type        = list(string)
}

variable "cluster_role_arn" {
  description = "ARN of the IAM role for the EKS cluster"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the IAM role for the EKS node group"
  type        = string
}

variable "endpoint_public_access" {
  description = "Whether the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the Amazon EKS public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_encryption" {
  description = "Enable envelope encryption of secrets in etcd"
  type        = bool
  default     = true
}

variable "node_group_config" {
  description = "Configuration for the EKS node group"
  type = object({
    desired_size             = number
    max_size                = number
    min_size                = number
    instance_types           = list(string)
    capacity_type            = string
    disk_size               = number
    ami_type                = string
    enable_remote_access    = bool
    ec2_ssh_key            = string
    source_security_group_ids = list(string)
  })
  default = {
    desired_size             = 3
    max_size                = 5
    min_size                = 2
    instance_types           = ["t4g.medium"]
    capacity_type            = "ON_DEMAND"
    disk_size               = 100
    ami_type                = "AL2023_ARM_64_STANDARD"
    enable_remote_access    = false
    ec2_ssh_key            = ""
    source_security_group_ids = []
  }
}

variable "use_launch_template" {
  description = "Whether to use a launch template for the node group"
  type        = bool
  default     = true
}

variable "node_labels" {
  description = "Key-value mapping of Kubernetes labels"
  type        = map(string)
  default     = {}
}

variable "enable_ssm_agent" {
  description = "Whether to install SSM agent on nodes"
  type        = bool
  default     = true
}

variable "additional_userdata" {
  description = "Additional user data script"
  type        = string
  default     = ""
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = false
}

# Add-on versions
variable "ebs_csi_driver_version" {
  description = "Version of the EBS CSI driver add-on"
  type        = string
  default     = null # Uses latest if not specified
}

variable "vpc_cni_version" {
  description = "Version of the VPC CNI add-on"
  type        = string
  default     = null
}

variable "kube_proxy_version" {
  description = "Version of the kube-proxy add-on"
  type        = string
  default     = null
}

variable "coredns_version" {
  description = "Version of the CoreDNS add-on"
  type        = string
  default     = null
}

variable "cloudwatch_observability_version" {
  description = "Version of the CloudWatch Observability add-on"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}