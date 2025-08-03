# 10 - Autoscaling Configuration with Scale-to-Zero

# HPA for Processor Slaves (Scale-to-Zero)
resource "kubernetes_horizontal_pod_autoscaler_v2" "processor_slaves" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-slaves-hpa"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.processor_slaves[0].metadata[0].name
    }

    min_replicas = 0  # Scale to zero when idle
    max_replicas = 10

    # Scale up when Kafka lag exceeds threshold
    metric {
      type = "External"
      external {
        metric {
          name = "kafka_consumer_lag_sum"
          selector {
            match_labels = {
              topic          = "aurora-logs"
              consumer_group = "processor-slaves"
            }
          }
        }
        target {
          type  = "Value"
          value = "1000"
        }
      }
    }

    # Scale based on CPU (when pods exist)
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    # Scale based on memory (when pods exist)
    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    # Aggressive scale-down behavior
    behavior {
      scale_down {
        stabilization_window_seconds = 60  # Very short window
        
        policy {
          type          = "Percent"
          value         = 100  # Scale down 100% at once
          period_seconds = 15
        }
        
        policy {
          type          = "Pods"
          value         = 10  # Remove up to 10 pods at once
          period_seconds = 60
        }
        
        select_policy = "Max"  # Use most aggressive policy
      }

      scale_up {
        stabilization_window_seconds = 0  # No stabilization, scale immediately
        
        policy {
          type          = "Percent"
          value         = 200  # Double the pods
          period_seconds = 15
        }
        
        policy {
          type          = "Pods"
          value         = 5  # Add 5 pods at once
          period_seconds = 15
        }
        
        select_policy = "Max"
      }
    }
  }
}

# HPA for Discovery Service
resource "kubernetes_horizontal_pod_autoscaler_v2" "discovery" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "discovery-hpa"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.discovery[0].metadata[0].name
    }

    min_replicas = 1  # Always keep 1 for continuous discovery
    max_replicas = 3

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 85
        }
      }
    }
  }
}

# VPA for OpenObserve (optimize resource requests)
resource "kubernetes_manifest" "openobserve_vpa" {
  count = var.deploy_k8s_resources && var.enable_vpa ? 1 : 0

  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = "openobserve-vpa"
      namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = kubernetes_deployment.openobserve[0].metadata[0].name
      }
      updatePolicy = {
        updateMode = "Auto"
      }
      resourcePolicy = {
        containerPolicies = [{
          containerName = "openobserve"
          minAllowed = {
            cpu    = "200m"
            memory = "1Gi"
          }
          maxAllowed = {
            cpu    = "2000m"
            memory = "8Gi"
          }
        }]
      }
    }
  }
}

# VPA for Kafka (optimize resource requests)
resource "kubernetes_manifest" "kafka_vpa" {
  count = var.deploy_k8s_resources && var.enable_vpa ? 1 : 0

  manifest = {
    apiVersion = "autoscaling.k8s.io/v1"
    kind       = "VerticalPodAutoscaler"
    metadata = {
      name      = "kafka-vpa"
      namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    }
    spec = {
      targetRef = {
        apiVersion = "apps/v1"
        kind       = "Deployment"
        name       = kubernetes_deployment.kafka[0].metadata[0].name
      }
      updatePolicy = {
        updateMode = "Auto"
      }
      resourcePolicy = {
        containerPolicies = [{
          containerName = "kafka"
          minAllowed = {
            cpu    = "100m"
            memory = "512Mi"
          }
          maxAllowed = {
            cpu    = "1000m"
            memory = "4Gi"
          }
        }]
      }
    }
  }
}

# Cluster Autoscaler configuration for EKS
resource "kubernetes_config_map" "cluster_autoscaler_status" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "cluster-autoscaler-status"
    namespace = "kube-system"
  }

  data = {
    # Configuration for aggressive scale-down
    "scale-down-delay-after-add"       = "2m"
    "scale-down-unneeded-time"         = "2m"
    "scale-down-utilization-threshold" = "0.7"
    "skip-nodes-with-system-pods"      = "false"
    "balance-similar-node-groups"      = "true"
    "expander"                         = "least-waste"
  }
}

# KEDA ScaledObject for advanced Kafka-based scaling
resource "kubernetes_manifest" "processor_slaves_scaledobject" {
  count = var.deploy_k8s_resources && var.enable_keda ? 1 : 0

  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "processor-slaves-kafka-scaler"
      namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    }
    spec = {
      scaleTargetRef = {
        name = kubernetes_deployment.processor_slaves[0].metadata[0].name
      }
      minReplicaCount = 0
      maxReplicaCount = 10
      cooldownPeriod  = 60
      pollingInterval = 30
      
      triggers = [{
        type = "kafka"
        metadata = {
          bootstrapServers = "kafka-service.${var.k8s_namespace}.svc.cluster.local:9092"
          consumerGroup    = "processor-slaves"
          topic            = "aurora-logs"
          lagThreshold     = "100"
          offsetResetPolicy = "earliest"
        }
      }]
      
      advanced = {
        horizontalPodAutoscalerConfig = {
          behavior = {
            scaleDown = {
              stabilizationWindowSeconds = 60
              policies = [{
                type  = "Percent"
                value = 100
                periodSeconds = 15
              }]
            }
            scaleUp = {
              stabilizationWindowSeconds = 0
              policies = [{
                type  = "Percent"
                value = 200
                periodSeconds = 15
              }]
            }
          }
        }
      }
    }
  }
}

# Priority Classes for cost optimization
resource "kubernetes_priority_class" "high_priority" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name = "aurora-high-priority"
  }

  value             = 1000
  global_default    = false
  description       = "High priority class for critical Aurora Log System components"
  
  # Preemption policy to save costs
  preemption_policy = "PreemptLowerPriority"
}

resource "kubernetes_priority_class" "low_priority" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name = "aurora-low-priority"
  }

  value             = 100
  global_default    = false
  description       = "Low priority class for non-critical workloads"
  
  # Can be preempted to save costs
  preemption_policy = "Never"
}

# Variables for autoscaling features
variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler"
  type        = bool
  default     = false
}

variable "enable_keda" {
  description = "Enable KEDA for advanced autoscaling"
  type        = bool
  default     = false
}