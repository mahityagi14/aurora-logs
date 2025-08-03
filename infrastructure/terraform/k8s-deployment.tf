# Kubernetes Deployment for Aurora Log System
# This file deploys all K8s resources using Terraform

# Configure kubectl provider
provider "kubectl" {
  host                   = data.aws_eks_cluster.existing.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.existing.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.existing.token
  load_config_file       = false
}

# Variables for K8s deployment
variable "deploy_k8s_resources" {
  description = "Whether to deploy Kubernetes resources"
  type        = bool
  default     = true
}

variable "k8s_namespace" {
  description = "Kubernetes namespace for Aurora Log System"
  type        = string
  default     = "aurora-logs"
}

variable "enable_cost_optimization" {
  description = "Enable cost optimization features (scale-to-zero, minimal resources)"
  type        = bool
  default     = true
}

variable "enable_fargate" {
  description = "Enable Fargate for processor slaves"
  type        = bool
  default     = false
}

# Local variables for K8s resources
locals {
  k8s_labels = {
    "app.kubernetes.io/name"       = "aurora-log-system"
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "aurora-logs"
  }

  # Resource limits based on cost optimization
  resource_limits = {
    discovery = {
      cpu    = var.enable_cost_optimization ? "200m" : "500m"
      memory = var.enable_cost_optimization ? "256Mi" : "512Mi"
    }
    processor_master = {
      cpu    = var.enable_cost_optimization ? "300m" : "500m"
      memory = var.enable_cost_optimization ? "512Mi" : "1Gi"
    }
    processor_slave = {
      cpu    = var.enable_cost_optimization ? "200m" : "500m"
      memory = var.enable_cost_optimization ? "256Mi" : "512Mi"
    }
    kafka = {
      cpu    = var.enable_cost_optimization ? "500m" : "1000m"
      memory = var.enable_cost_optimization ? "2Gi" : "4Gi"
    }
    openobserve = {
      cpu    = var.enable_cost_optimization ? "1000m" : "2000m"
      memory = var.enable_cost_optimization ? "4Gi" : "8Gi"
    }
    valkey = {
      cpu    = var.enable_cost_optimization ? "200m" : "500m"
      memory = var.enable_cost_optimization ? "512Mi" : "1Gi"
    }
  }

  # Resource requests (50% of limits for cost optimization)
  resource_requests = {
    discovery = {
      cpu    = var.enable_cost_optimization ? "50m" : "100m"
      memory = var.enable_cost_optimization ? "128Mi" : "256Mi"
    }
    processor_master = {
      cpu    = var.enable_cost_optimization ? "100m" : "200m"
      memory = var.enable_cost_optimization ? "256Mi" : "512Mi"
    }
    processor_slave = {
      cpu    = var.enable_cost_optimization ? "50m" : "100m"
      memory = var.enable_cost_optimization ? "128Mi" : "256Mi"
    }
    kafka = {
      cpu    = var.enable_cost_optimization ? "200m" : "500m"
      memory = var.enable_cost_optimization ? "1Gi" : "2Gi"
    }
    openobserve = {
      cpu    = var.enable_cost_optimization ? "500m" : "1000m"
      memory = var.enable_cost_optimization ? "2Gi" : "4Gi"
    }
    valkey = {
      cpu    = var.enable_cost_optimization ? "50m" : "100m"
      memory = var.enable_cost_optimization ? "128Mi" : "256Mi"
    }
  }
}

# Deploy K8s resources only if enabled
resource "null_resource" "k8s_deployment" {
  count = var.deploy_k8s_resources ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'K8s deployment would start here. Use kubernetes_manifest resources below.'"
  }
}

# 00 - Namespace and RBAC
resource "kubernetes_namespace" "aurora_logs" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name = var.k8s_namespace
    labels = merge(local.k8s_labels, {
      "name" = var.k8s_namespace
    })
  }
}

# Service Accounts with IAM roles
resource "kubernetes_service_account" "discovery" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "discovery-sa"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aurora-logs-poc-discovery-role"
    }
  }
}

resource "kubernetes_service_account" "processor" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-sa"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aurora-logs-poc-processor-role"
    }
  }
}

resource "kubernetes_service_account" "openobserve" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-sa"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aurora-logs-poc-openobserve-role"
    }
  }
}

# 01 - Secrets
resource "kubernetes_secret" "app_secrets" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "app-secrets"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    KAFKA_USERNAME = "admin"
    KAFKA_PASSWORD = "admin-secret"
  }

  type = "Opaque"
}

resource "kubernetes_secret" "openobserve_credentials" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-credentials"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "admin-email"    = "admin@example.com"
    "admin-password" = "Complexpass#123"
  }

  type = "Opaque"
}

resource "kubernetes_secret" "openobserve_secret" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-secret"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    token = base64encode("admin@example.com:Complexpass#123")
  }

  type = "Opaque"
}

# 02 - ConfigMaps
resource "kubernetes_config_map" "app_config" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    # DynamoDB Tables
    INSTANCE_TABLE = local.dynamodb_tables.instance_metadata
    TRACKING_TABLE = local.dynamodb_tables.tracking
    JOBS_TABLE     = local.dynamodb_tables.jobs

    # S3 Configuration
    S3_BUCKET = local.s3_buckets.aurora_logs
    S3_PREFIX = "aurora-logs/"

    # AWS Configuration
    AWS_REGION = var.region

    # Kafka Configuration
    KAFKA_BROKERS             = "kafka-service.${var.k8s_namespace}.svc.cluster.local:9092"
    KAFKA_TOPIC               = "aurora-logs"
    KAFKA_CONSUMER_GROUP      = "aurora-log-processor"
    KAFKA_SESSION_TIMEOUT     = "30000"
    KAFKA_AUTO_OFFSET_RESET   = "earliest"
    KAFKA_ENABLE_AUTO_COMMIT  = "false"
    KAFKA_MAX_POLL_RECORDS    = "100"

    # OpenObserve Configuration
    OPENOBSERVE_URL           = "http://openobserve-service.${var.k8s_namespace}.svc.cluster.local:5080"
    OPENOBSERVE_ORGANIZATION  = "default"
    OPENOBSERVE_STREAM_NAME   = "aurora-logs"
    
    # Valkey Configuration
    VALKEY_HOST = module.elasticache.primary_endpoint_address
    VALKEY_PORT = "6379"
    
    # Processing Configuration
    BATCH_SIZE           = "100"
    BATCH_TIMEOUT        = "30s"
    MAX_RETRIES          = "3"
    RETRY_DELAY          = "5s"
    WORKER_POOL_SIZE     = "10"
    
    # Discovery Configuration
    DISCOVERY_INTERVAL   = "300"
    MAX_LOG_FILES        = "100"
    LOG_FILE_MIN_SIZE    = "1024"
    
    # Health Check
    HEALTH_CHECK_PORT    = "8080"
    METRICS_PORT         = "9090"
    
    # Logging
    LOG_LEVEL            = "info"
    LOG_FORMAT           = "json"
    
    # OTEL Configuration
    OTEL_ENABLED         = "true"
    OTEL_SERVICE_NAME    = "aurora-log-system"
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://openobserve-service.${var.k8s_namespace}.svc.cluster.local:5080/api/default/v1/traces"
    METRICS_PORT         = "9090"
    
    # Feature Flags
    ENABLE_PROFILING     = "false"
    ENABLE_CACHING       = "true"
    ENABLE_COMPRESSION   = "true"
  }
}

# 03 - Storage (PVCs)
resource "kubernetes_persistent_volume_claim" "openobserve_data" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-data-pvc"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "gp3"
    
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "kafka_data" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "kafka-data-pvc"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "gp3"
    
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

# Output connection information
output "k8s_namespace" {
  value = var.deploy_k8s_resources ? kubernetes_namespace.aurora_logs[0].metadata[0].name : ""
}

output "openobserve_access" {
  value = var.deploy_k8s_resources ? {
    command  = "kubectl port-forward -n ${var.k8s_namespace} svc/openobserve-service 5080:5080"
    url      = "http://localhost:5080"
    username = "admin@example.com"
    password = "Complexpass#123"
  } : null
}

output "deployment_status" {
  value = var.deploy_k8s_resources ? "Kubernetes resources deployed" : "Kubernetes deployment skipped"
}