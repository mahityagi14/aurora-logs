# Kubernetes Services Deployment (04-08)
# Valkey, Kafka, OpenObserve, Discovery, and Processor

# 04 - Valkey Service
resource "kubernetes_service" "valkey" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "valkey-service"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    selector = {
      app = "valkey"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "valkey" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "valkey"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "valkey"
      }
    }

    template {
      metadata {
        labels = {
          app = "valkey"
        }
      }

      spec {
        container {
          name  = "valkey"
          image = "valkey/valkey:8.1.3"

          port {
            container_port = 6379
            name          = "redis"
          }

          resources {
            requests = {
              cpu    = local.resource_requests.valkey.cpu
              memory = local.resource_requests.valkey.memory
            }
            limits = {
              cpu    = local.resource_limits.valkey.cpu
              memory = local.resource_limits.valkey.memory
            }
          }

          env {
            name  = "VALKEY_PASSWORD"
            value = ""  # No password for internal use
          }

          command = ["valkey-server"]
          args = [
            "--maxmemory", "400mb",
            "--maxmemory-policy", "allkeys-lru",
            "--save", "",
            "--appendonly", "no"
          ]

          liveness_probe {
            tcp_socket {
              port = 6379
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "valkey-cli ping | grep PONG"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# 05 - Kafka Service (Cost-optimized single node)
resource "kubernetes_service" "kafka" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "kafka-service"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    selector = {
      app = "kafka"
    }

    port {
      name        = "kafka"
      port        = 9092
      target_port = 9092
    }

    port {
      name        = "controller"
      port        = 9093
      target_port = 9093
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "kafka" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "kafka"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app       = "kafka"
      component = "message-broker"
    }
  }

  spec {
    replicas = 1  # Single node for cost savings

    selector {
      match_labels = {
        app = "kafka"
      }
    }

    template {
      metadata {
        labels = {
          app  = "kafka"
          tier = "messaging"
        }
      }

      spec {
        init_container {
          name  = "kafka-init"
          image = "aurora-kafka:latest"
          
          command = ["sh", "-c", <<-EOT
            echo "Initializing Kafka storage..."
            KAFKA_CLUSTER_ID="MkU3OEVBNzE0QTI2Qjk2NA"
            /opt/bitnami/kafka/bin/kafka-storage.sh format -t $KAFKA_CLUSTER_ID -c /opt/bitnami/kafka/config/kraft/server.properties || true
            echo "Storage initialization complete"
          EOT
          ]

          volume_mount {
            name       = "kafka-data"
            mount_path = "/var/lib/kafka"
          }
        }

        container {
          name  = "kafka"
          image = "aurora-kafka:latest"
          image_pull_policy = "Always"

          port {
            name           = "kafka"
            container_port = 9092
          }

          port {
            name           = "controller"
            container_port = 9093
          }

          resources {
            requests = {
              cpu    = local.resource_requests.kafka.cpu
              memory = local.resource_requests.kafka.memory
            }
            limits = {
              cpu    = local.resource_limits.kafka.cpu
              memory = local.resource_limits.kafka.memory
            }
          }

          env {
            name  = "KAFKA_CFG_NODE_ID"
            value = "1"
          }

          env {
            name  = "KAFKA_CFG_PROCESS_ROLES"
            value = "broker,controller"
          }

          env {
            name  = "KAFKA_CFG_LISTENERS"
            value = "PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093"
          }

          env {
            name  = "KAFKA_CFG_ADVERTISED_LISTENERS"
            value = "PLAINTEXT://kafka-service.${var.k8s_namespace}.svc.cluster.local:9092"
          }

          env {
            name  = "KAFKA_CFG_CONTROLLER_QUORUM_VOTERS"
            value = "1@kafka-service.${var.k8s_namespace}.svc.cluster.local:9093"
          }

          env {
            name  = "KAFKA_HEAP_OPTS"
            value = "-Xmx768M -Xms512M"
          }

          env {
            name  = "KAFKA_CFG_LOG_RETENTION_HOURS"
            value = "24"
          }

          env {
            name  = "KAFKA_CFG_COMPRESSION_TYPE"
            value = "lz4"
          }

          volume_mount {
            name       = "kafka-data"
            mount_path = "/var/lib/kafka"
          }

          liveness_probe {
            tcp_socket {
              port = 9092
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }

          readiness_probe {
            exec {
              command = ["sh", "-c", "/opt/bitnami/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          startup_probe {
            tcp_socket {
              port = 9092
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 30
          }
        }

        volume {
          name = "kafka-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.kafka_data[0].metadata[0].name
          }
        }
      }
    }
  }
}

# 06 - OpenObserve Service
resource "kubernetes_service" "openobserve" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve-service"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app       = "openobserve"
      component = "log-analytics"
    }
  }

  spec {
    selector = {
      app = "openobserve"
    }

    port {
      name        = "http"
      port        = 5080
      target_port = 5080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "openobserve" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "openobserve"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app       = "openobserve"
      component = "log-analytics"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "openobserve"
      }
    }

    template {
      metadata {
        labels = {
          app       = "openobserve"
          component = "log-analytics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.openobserve[0].metadata[0].name

        container {
          name  = "openobserve"
          image = "public.ecr.aws/zinclabs/openobserve:v0.15.0"

          port {
            name           = "http"
            container_port = 5080
          }

          resources {
            requests = {
              cpu    = local.resource_requests.openobserve.cpu
              memory = local.resource_requests.openobserve.memory
            }
            limits = {
              cpu    = local.resource_limits.openobserve.cpu
              memory = local.resource_limits.openobserve.memory
            }
          }

          env {
            name  = "ZO_ROOT_USER_EMAIL"
            value = "admin@example.com"
          }

          env {
            name  = "ZO_ROOT_USER_PASSWORD"
            value = "Complexpass#123"
          }

          env {
            name  = "ZO_S3_BUCKET_NAME"
            value = local.s3_buckets.aurora_logs
          }

          env {
            name  = "ZO_S3_REGION_NAME"
            value = var.region
          }

          env {
            name  = "ZO_S3_PROVIDER"
            value = "aws"
          }

          env {
            name  = "ZO_LOCAL_MODE_STORAGE"
            value = "disk"
          }

          env {
            name  = "ZO_MEMORY_CACHE_ENABLED"
            value = "true"
          }

          env {
            name  = "ZO_MEMORY_CACHE_MAX_SIZE"
            value = "512"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5080
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.openobserve_data[0].metadata[0].name
          }
        }
      }
    }
  }
}

# 07 - Discovery Service
resource "kubernetes_service" "discovery" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "discovery-service"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app       = "discovery"
      component = "log-collector"
    }
  }

  spec {
    selector = {
      app = "discovery"
    }

    port {
      name        = "metrics"
      port        = 9090
      target_port = 9090
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "discovery" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "discovery"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app       = "discovery"
      component = "log-collector"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "discovery"
      }
    }

    template {
      metadata {
        labels = {
          app       = "discovery"
          component = "log-collector"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.discovery[0].metadata[0].name

        container {
          name  = "discovery"
          image = "aurora-discovery:latest"
          image_pull_policy = "Always"

          port {
            name           = "metrics"
            container_port = 9090
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = local.resource_requests.discovery.cpu
              memory = local.resource_requests.discovery.memory
            }
            limits = {
              cpu    = local.resource_limits.discovery.cpu
              memory = local.resource_limits.discovery.memory
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

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
            read_only  = false
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "1Gi"
          }
        }
      }
    }
  }
}