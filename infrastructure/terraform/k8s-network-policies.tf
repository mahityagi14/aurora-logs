# 11 - Network Policies

# Default deny all ingress traffic
resource "kubernetes_network_policy" "default_deny_ingress" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

# Allow ingress for OpenObserve
resource "kubernetes_network_policy" "openobserve_ingress" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "openobserve-ingress"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "openobserve"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow from processors and fluent-bit
      from {
        pod_selector {
          match_labels = {
            app = "processor"
          }
        }
      }
      
      from {
        pod_selector {
          match_labels = {
            app = "fluent-bit"
          }
        }
      }
      
      # Allow from ingress controller
      from {
        namespace_selector {
          match_labels = {
            name = "ingress-nginx"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "5080"
      }
    }
  }
}

# Allow ingress for Kafka
resource "kubernetes_network_policy" "kafka_ingress" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "kafka-ingress"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "kafka"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow from discovery and processor services
      from {
        pod_selector {
          match_labels = {
            app = "discovery"
          }
        }
      }
      
      from {
        pod_selector {
          match_labels = {
            app = "processor"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "9092"
      }
      
      ports {
        protocol = "TCP"
        port     = "9093"
      }
    }
  }
}

# Allow ingress for Valkey
resource "kubernetes_network_policy" "valkey_ingress" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "valkey-ingress"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "valkey"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow from discovery and processor services
      from {
        pod_selector {
          match_labels = {
            app = "discovery"
          }
        }
      }
      
      from {
        pod_selector {
          match_labels = {
            app = "processor"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "6379"
      }
    }
  }
}

# Allow processor master-slave communication
resource "kubernetes_network_policy" "processor_internal" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "processor-internal"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "processor"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow processor pods to communicate with each other
      from {
        pod_selector {
          match_labels = {
            app = "processor"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "8080"
      }
      
      ports {
        protocol = "TCP"
        port     = "9090"
      }
    }
  }
}

# Allow Fluent Bit sidecar communication
resource "kubernetes_network_policy" "fluent_bit_sidecar" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "fluent-bit-sidecar"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "fluent-bit"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      # Allow from processor slaves (TCP forward)
      from {
        pod_selector {
          match_labels = {
            app  = "processor"
            role = "slave"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "24224"
      }
    }
  }
}

# Allow egress to AWS services
resource "kubernetes_network_policy" "aws_egress" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "aws-egress"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      # Allow DNS
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    egress {
      # Allow HTTPS to AWS services
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }

    egress {
      # Allow internal cluster communication
      to {
        pod_selector {}
      }
    }
  }
}

# Allow metrics scraping
resource "kubernetes_network_policy" "metrics_scraping" {
  count = var.deploy_k8s_resources && var.enable_network_policies ? 1 : 0

  metadata {
    name      = "metrics-scraping"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      # Allow from Prometheus/monitoring namespace
      from {
        namespace_selector {
          match_labels = {
            name = "monitoring"
          }
        }
      }

      # Allow from kube-system for metrics-server
      from {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = "9090"
      }
      
      ports {
        protocol = "TCP"
        port     = "2020"
      }
    }
  }
}

# Variable for network policies
variable "enable_network_policies" {
  description = "Enable network policies for pod-to-pod communication"
  type        = bool
  default     = true
}