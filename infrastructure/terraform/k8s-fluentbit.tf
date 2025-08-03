# 09 - Fluent Bit Configuration

# ConfigMap for Fluent Bit configuration
resource "kubernetes_config_map" "fluent_bit_config" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "fluent-bit-config"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "fluent-bit.conf" = <<-EOT
      [SERVICE]
          Flush                1
          Log_Level            info
          Daemon               off
          Parsers_File         parsers.conf
          HTTP_Server          On
          HTTP_Listen          0.0.0.0
          HTTP_Port            2020
          storage.metrics      on

      [INPUT]
          Name                 forward
          Listen               0.0.0.0
          Port                 24224
          Buffer_Chunk_Size    1M
          Buffer_Max_Size      6M
          Tag_Prefix           aurora.

      [INPUT]
          Name                 tail
          Path                 /var/log/containers/*_${var.k8s_namespace}_*.log
          Parser               cri
          Tag                  k8s.*
          Refresh_Interval     5
          Mem_Buf_Limit        50MB
          Skip_Long_Lines      On
          DB                   /var/log/flb-k8s.db
          DB.Sync              Normal

      [FILTER]
          Name                 kubernetes
          Match                k8s.*
          Kube_URL             https://kubernetes.default.svc:443
          Kube_CA_File         /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
          Kube_Token_File      /var/run/secrets/kubernetes.io/serviceaccount/token
          Kube_Tag_Prefix      k8s.var.log.containers.
          Merge_Log            On
          Keep_Log             Off
          K8S-Logging.Parser   On
          K8S-Logging.Exclude  On
          Buffer_Size          1MB

      [FILTER]
          Name                 lua
          Match                aurora.*
          script               timestamp_parser.lua
          call                 extract_timestamp

      [FILTER]
          Name                 modify
          Match                k8s.*
          Add                  _index_name k8s-logs
          Add                  _stream_name ${var.k8s_namespace}

      [OUTPUT]
          Name                 http
          Match                aurora.*
          Host                 openobserve-service.${var.k8s_namespace}.svc.cluster.local
          Port                 5080
          URI                  /api/default/aurora-logs/_multi
          Format               json
          Json_date_format     epoch
          Json_date_key        timestamp
          HTTP_User            admin@example.com
          HTTP_Passwd          Complexpass#123
          tls                  off
          Retry_Limit          5

      [OUTPUT]
          Name                 s3
          Match                k8s.*
          bucket               ${local.s3_buckets.k8s_logs}
          region               ${var.region}
          use_put_object       On
          total_file_size      50M
          upload_timeout       10m
          compression          gzip
          content_type         application/json
          s3_key_format        /k8s-logs/%Y/%m/%d/$${hostname}_%Y%m%d-%H%M%S_$${tag}.gz
    EOT

    "parsers.conf" = <<-EOT
      [PARSER]
          Name         cri
          Format       regex
          Regex        ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
          Time_Key     time
          Time_Format  %Y-%m-%dT%H:%M:%S.%L%z
          Time_Keep    On

      [PARSER]
          Name         json
          Format       json
          Time_Key     timestamp
          Time_Format  %Y-%m-%dT%H:%M:%S.%L%z
          Time_Keep    On

      [PARSER]
          Name         aurora_timestamp
          Format       regex
          Regex        ^(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+(?<message>.*)$
          Time_Key     timestamp
          Time_Format  %Y-%m-%dT%H:%M:%S.%LZ
          Time_Keep    On
    EOT

    "timestamp_parser.lua" = <<-EOT
      function extract_timestamp(tag, timestamp, record)
          -- Try to extract timestamp from the log line
          local line = record["log"] or record["message"] or ""
          
          -- Pattern: 2025-01-30T12:34:56.789Z
          local ts_pattern = "(%d%d%d%d%-[01]%d%-[0-3]%d[T ]%d%d:%d%d:%d%d%.%d%d%d)Z?"
          local extracted_ts = string.match(line, ts_pattern)
          
          if extracted_ts then
              -- Convert to epoch milliseconds
              local year, month, day, hour, min, sec, msec = string.match(extracted_ts, 
                  "(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)%.(%d%d%d)")
              
              if year then
                  local t = os.time{year=year, month=month, day=day, hour=hour, min=min, sec=sec}
                  if t then
                      record["timestamp"] = t * 1000 + tonumber(msec)
                      record["original_timestamp"] = extracted_ts .. "Z"
                  end
              end
          end
          
          -- Ensure timestamp exists
          if not record["timestamp"] then
              record["timestamp"] = timestamp * 1000
          end
          
          return 2, timestamp, record
      end
    EOT
  }
}

# DaemonSet for K8s log collection
resource "kubernetes_daemonset" "fluent_bit" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    labels = {
      app = "fluent-bit"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "fluent-bit"
      }
    }

    template {
      metadata {
        labels = {
          app = "fluent-bit"
        }
        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "2020"
          "prometheus.io/path"   = "/api/v1/metrics/prometheus"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.fluent_bit[0].metadata[0].name

        toleration {
          key      = "node-role.kubernetes.io/master"
          effect   = "NoSchedule"
          operator = "Exists"
        }

        toleration {
          operator = "Exists"
          effect   = "NoExecute"
        }

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name  = "fluent-bit"
          image = "fluent/fluent-bit:3.2.2"

          resources {
            requests = {
              cpu    = "20m"
              memory = "100Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "500Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/"
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }

          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }

          volume_mount {
            name       = "fluent-bit-state"
            mount_path = "/var/fluent-bit/state"
          }

          volume_mount {
            name       = "runlog"
            mount_path = "/run/log"
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
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

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.fluent_bit_config[0].metadata[0].name
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }

        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }

        volume {
          name = "fluent-bit-state"
          host_path {
            path = "/var/fluent-bit/state"
            type = "DirectoryOrCreate"
          }
        }

        volume {
          name = "runlog"
          host_path {
            path = "/run/log"
          }
        }

        host_network = true
        dns_policy   = "ClusterFirstWithHostNet"
      }
    }
  }
}

# Service Account for Fluent Bit
resource "kubernetes_service_account" "fluent_bit" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "fluent-bit"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aurora-logs-poc-fluent-bit-role"
    }
  }
}

# ClusterRole for Fluent Bit
resource "kubernetes_cluster_role" "fluent_bit" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name = "fluent-bit-${var.k8s_namespace}"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "pods/logs", "nodes", "nodes/proxy"]
    verbs      = ["get", "list", "watch"]
  }
}

# ClusterRoleBinding for Fluent Bit
resource "kubernetes_cluster_role_binding" "fluent_bit" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name = "fluent-bit-${var.k8s_namespace}"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.fluent_bit[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.fluent_bit[0].metadata[0].name
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }
}