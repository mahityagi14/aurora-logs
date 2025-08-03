# 12 - Combined Policies (PodDisruptionBudgets and ResourceQuotas)

# PodDisruptionBudgets for high availability

# PDB for Kafka - always available
resource "kubernetes_pod_disruption_budget_v1" "kafka" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "kafka-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "kafka"
      }
    }
  }
}

# PDB for OpenObserve - always available
resource "kubernetes_pod_disruption_budget_v1" "openobserve" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "openobserve"
      }
    }
  }
}

# PDB for Processor Master - always available
resource "kubernetes_pod_disruption_budget_v1" "processor_master" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-master-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app  = "processor"
        role = "master"
      }
    }
  }
}

# PDB for Processor Slaves - allow disruption when scaled
resource "kubernetes_pod_disruption_budget_v1" "processor_slaves" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-slaves-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    max_unavailable = "50%"
    
    selector {
      match_labels = {
        app  = "processor"
        role = "slave"
      }
    }
  }
}

# PDB for Discovery - always keep at least 1
resource "kubernetes_pod_disruption_budget_v1" "discovery" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "discovery-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "discovery"
      }
    }
  }
}

# PDB for Valkey
resource "kubernetes_pod_disruption_budget_v1" "valkey" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "valkey-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    min_available = 1
    
    selector {
      match_labels = {
        app = "valkey"
      }
    }
  }
}

# PDB for Fluent Bit DaemonSet
resource "kubernetes_pod_disruption_budget_v1" "fluent_bit" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "fluent-bit-pdb"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    max_unavailable = "30%"  # Allow 30% disruption for rolling updates
    
    selector {
      match_labels = {
        app = "fluent-bit"
      }
    }
  }
}

# ResourceQuotas for namespace protection

# Resource quota for the aurora-logs namespace
resource "kubernetes_resource_quota" "aurora_logs" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "aurora-logs-quota"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    hard = {
      # CPU and Memory limits
      "requests.cpu"    = var.enable_cost_optimization ? "4" : "10"
      "requests.memory" = var.enable_cost_optimization ? "16Gi" : "32Gi"
      "limits.cpu"      = var.enable_cost_optimization ? "8" : "20"
      "limits.memory"   = var.enable_cost_optimization ? "32Gi" : "64Gi"
      
      # Storage limits
      "requests.storage"          = "50Gi"
      "persistentvolumeclaims"    = "10"
      
      # Object count limits
      "pods"                      = "50"
      "services"                  = "20"
      "configmaps"                = "20"
      "secrets"                   = "20"
      "services.loadbalancers"    = "0"  # No LoadBalancers for cost
      "services.nodeports"        = "0"  # No NodePorts for security
    }
    
    # Scope to exclude DaemonSet pods from quota
    scope_selector {
      scope_name = "NotBestEffort"
    }
  }
}

# Limit ranges for default resource constraints
resource "kubernetes_limit_range" "aurora_logs" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "aurora-logs-limits"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    # Container limits
    limit {
      type = "Container"
      
      default = {
        cpu    = var.enable_cost_optimization ? "200m" : "500m"
        memory = var.enable_cost_optimization ? "512Mi" : "1Gi"
      }
      
      default_request = {
        cpu    = var.enable_cost_optimization ? "50m" : "100m"
        memory = var.enable_cost_optimization ? "128Mi" : "256Mi"
      }
      
      max = {
        cpu    = "2000m"
        memory = "8Gi"
      }
      
      min = {
        cpu    = "10m"
        memory = "64Mi"
      }
    }
    
    # Pod limits
    limit {
      type = "Pod"
      
      max = {
        cpu    = "4000m"
        memory = "16Gi"
      }
      
      min = {
        cpu    = "10m"
        memory = "64Mi"
      }
    }
    
    # PVC limits
    limit {
      type = "PersistentVolumeClaim"
      
      max = {
        storage = "20Gi"
      }
      
      min = {
        storage = "1Gi"
      }
    }
  }
}

# Additional quota for monitoring/metrics if enabled
resource "kubernetes_resource_quota" "monitoring" {
  count = var.deploy_k8s_resources && var.enable_monitoring ? 1 : 0

  metadata {
    name      = "monitoring-quota"
    namespace = "monitoring"
  }

  spec {
    hard = {
      "requests.cpu"    = "2"
      "requests.memory" = "4Gi"
      "limits.cpu"      = "4"
      "limits.memory"   = "8Gi"
    }
  }
}

variable "enable_monitoring" {
  description = "Enable monitoring namespace and resources"
  type        = bool
  default     = false
}