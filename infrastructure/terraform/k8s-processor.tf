# 08 - Processor Master-Slave Architecture

# Processor Master Deployment
resource "kubernetes_deployment" "processor_master" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-master"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app  = "processor"
      tier = "master"
    }
  }

  spec {
    replicas = 1  # Always exactly 1 master

    selector {
      match_labels = {
        app  = "processor"
        role = "master"
      }
    }

    template {
      metadata {
        labels = {
          app  = "processor"
          role = "master"
          tier = "control"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.processor[0].metadata[0].name

        affinity {
          node_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              preference {
                match_expressions {
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["t3.small", "t3a.small"]
                }
              }
            }
          }
        }

        container {
          name              = "processor"
          image             = "aurora-processor:latest"
          image_pull_policy = "Always"

          resources {
            requests = {
              cpu    = local.resource_requests.processor_master.cpu
              memory = local.resource_requests.processor_master.memory
            }
            limits = {
              cpu    = local.resource_limits.processor_master.cpu
              memory = local.resource_limits.processor_master.memory
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config[0].metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets[0].metadata[0].name
            }
          }

          # Master-specific configuration
          env {
            name  = "PROCESSOR_ROLE"
            value = "master"
          }

          env {
            name  = "PROCESSOR_MODE"
            value = "coordinator"
          }

          env {
            name  = "CONSUMER_GROUP"
            value = "processor-master"
          }

          env {
            name  = "KAFKA_PARTITION_ASSIGNMENT"
            value = "static"
          }

          env {
            name  = "MAX_BATCH_SIZE"
            value = "10"
          }

          env {
            name  = "GOMAXPROCS"
            value = "1"
          }

          env {
            name  = "LOG_FORWARD_ENABLED"
            value = "true"
          }

          env {
            name  = "PARSING_MODE"
            value = "passthrough"
          }

          port {
            name           = "metrics"
            container_port = 9090
          }

          port {
            name           = "health"
            container_port = 8080
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "health"
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "health"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}

# Processor Slaves Deployment
resource "kubernetes_deployment" "processor_slaves" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-slaves"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app  = "processor"
      tier = "slave"
    }
  }

  spec {
    replicas = var.enable_cost_optimization ? 0 : 1  # Start with 0 for cost optimization

    selector {
      match_labels = {
        app  = "processor"
        role = "slave"
      }
    }

    template {
      metadata {
        labels = {
          app  = "processor"
          role = "slave"
          tier = "worker"
        }
        annotations = var.enable_fargate ? {
          "eks.amazonaws.com/compute-type" = "fargate"
        } : {}
      }

      spec {
        service_account_name            = kubernetes_service_account.processor[0].metadata[0].name
        termination_grace_period_seconds = 30

        container {
          name              = "processor"
          image             = "aurora-processor:latest"
          image_pull_policy = "Always"

          resources {
            requests = {
              cpu    = local.resource_requests.processor_slave.cpu
              memory = local.resource_requests.processor_slave.memory
            }
            limits = {
              cpu    = local.resource_limits.processor_slave.cpu
              memory = local.resource_limits.processor_slave.memory
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.app_config[0].metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.app_secrets[0].metadata[0].name
            }
          }

          # Slave-specific configuration
          env {
            name  = "PROCESSOR_ROLE"
            value = "slave"
          }

          env {
            name  = "PROCESSOR_MODE"
            value = "worker"
          }

          env {
            name  = "CONSUMER_GROUP"
            value = "processor-slaves"
          }

          env {
            name  = "KAFKA_PARTITION_ASSIGNMENT"
            value = "dynamic"
          }

          env {
            name  = "MAX_BATCH_SIZE"
            value = "100"
          }

          env {
            name  = "PROCESSING_TIMEOUT"
            value = "300s"
          }

          env {
            name  = "GOMAXPROCS"
            value = "1"
          }

          env {
            name  = "LOG_FORWARD_ENABLED"
            value = "true"
          }

          env {
            name  = "PARSING_MODE"
            value = "passthrough"
          }
        }

        # Fluent Bit sidecar for slaves
        container {
          name              = "fluent-bit"
          image             = "fluent/fluent-bit:3.2.2"

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          port {
            name           = "forward"
            container_port = 24224
            protocol       = "TCP"
          }

          volume_mount {
            name       = "fluent-bit-config"
            mount_path = "/fluent-bit/etc/"
          }

          env {
            name = "OPENOBSERVE_AUTH"
            value_from {
              secret_key_ref {
                name = "fluent-bit-auth"
                key  = "auth-token"
              }
            }
          }
        }

        volume {
          name = "fluent-bit-config"
          config_map {
            name = "fluent-bit-config"
          }
        }
      }
    }
  }
}

# Service for processor metrics aggregation
resource "kubernetes_service" "processor_metrics" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-metrics"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app = "processor"
    }
  }

  spec {
    selector = {
      app = "processor"
    }

    port {
      name        = "metrics"
      port        = 9090
      target_port = 9090
    }

    type = "ClusterIP"
  }
}

# ConfigMap for master-slave coordination
resource "kubernetes_config_map" "processor_coordination" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "processor-coordination"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    # Coordination settings
    COORDINATION_ENABLED          = "true"
    MASTER_ENDPOINT              = "processor-master.${var.k8s_namespace}.svc.cluster.local:8080"
    SLAVE_REGISTRATION_INTERVAL  = "30s"
    PARTITION_REBALANCE_INTERVAL = "300s"
    
    # Load distribution
    MIN_PARTITIONS_PER_SLAVE    = "1"
    MAX_PARTITIONS_PER_SLAVE    = "3"
    LOAD_THRESHOLD_SCALE_UP     = "1000"
    LOAD_THRESHOLD_SCALE_DOWN   = "100"
    
    # Cost optimization
    IDLE_TIMEOUT             = "300s"
    BATCH_WAIT_TIMEOUT       = "30s"
    PROCESSING_CONCURRENCY   = "2"
  }
}

# Secret for Fluent Bit OpenObserve authentication
resource "kubernetes_secret" "fluent_bit_auth" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "fluent-bit-auth"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "auth-token" = base64encode("admin@example.com:Complexpass#123")
  }

  type = "Opaque"
}