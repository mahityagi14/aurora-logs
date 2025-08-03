# 13 - Monitoring (K8s logs to S3 and dashboards)

# ConfigMap for K8s log monitoring dashboards
resource "kubernetes_config_map" "monitoring_dashboards" {
  count = var.deploy_k8s_resources ? 1 : 0

  metadata {
    name      = "aurora-monitoring-dashboards"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "aurora-overview.json" = jsonencode({
      title = "Aurora Log System Overview"
      panels = [
        {
          title  = "Log Processing Rate"
          type   = "graph"
          query  = "rate(processor_logs_processed_total[5m])"
        },
        {
          title  = "Kafka Lag"
          type   = "graph"
          query  = "kafka_consumer_lag_sum"
        },
        {
          title  = "Pod Memory Usage"
          type   = "graph"
          query  = "container_memory_usage_bytes{namespace='${var.k8s_namespace}'}"
        },
        {
          title  = "Pod CPU Usage"
          type   = "graph"
          query  = "rate(container_cpu_usage_seconds_total{namespace='${var.k8s_namespace}'}[5m])"
        }
      ]
    })

    "cost-optimization.json" = jsonencode({
      title = "Cost Optimization Metrics"
      panels = [
        {
          title  = "Scaled-to-Zero Pods"
          type   = "stat"
          query  = "kube_deployment_status_replicas{deployment='processor-slaves',namespace='${var.k8s_namespace}'}"
        },
        {
          title  = "Resource Utilization"
          type   = "gauge"
          query  = "avg(container_cpu_usage_seconds_total{namespace='${var.k8s_namespace}'}) by (pod)"
        },
        {
          title  = "Storage Usage"
          type   = "stat"
          query  = "kubelet_volume_stats_used_bytes{namespace='${var.k8s_namespace}'}"
        },
        {
          title  = "Estimated Monthly Cost"
          type   = "stat"
          query  = "sum(kube_node_info) * 0.0464 * 24 * 30"
        }
      ]
    })

    "sla-monitoring.json" = jsonencode({
      title = "SLA Monitoring"
      panels = [
        {
          title  = "System Availability"
          type   = "stat"
          query  = "avg_over_time(up{namespace='${var.k8s_namespace}'}[7d]) * 100"
        },
        {
          title  = "Error Rate"
          type   = "graph"
          query  = "rate(processor_errors_total[5m])"
        },
        {
          title  = "Processing Latency"
          type   = "heatmap"
          query  = "histogram_quantile(0.99, processor_processing_duration_seconds_bucket)"
        },
        {
          title  = "Data Loss Prevention"
          type   = "stat"
          query  = "increase(kafka_consumer_records_consumed_total[1h]) - increase(openobserve_records_written_total[1h])"
        }
      ]
    })
  }
}

# ServiceMonitor for Prometheus scraping
resource "kubernetes_manifest" "service_monitor" {
  count = var.deploy_k8s_resources && var.enable_prometheus ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "aurora-logs-monitor"
      namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
      labels = {
        "prometheus" = "kube-prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/part-of" = "aurora-logs"
        }
      }
      endpoints = [{
        port     = "metrics"
        interval = "30s"
        path     = "/metrics"
      }]
    }
  }
}

# PrometheusRule for alerting
resource "kubernetes_manifest" "prometheus_rules" {
  count = var.deploy_k8s_resources && var.enable_prometheus ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "aurora-logs-alerts"
      namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
      labels = {
        "prometheus" = "kube-prometheus"
      }
    }
    spec = {
      groups = [{
        name = "aurora-logs"
        interval = "30s"
        rules = [
          {
            alert = "HighKafkaLag"
            expr  = "kafka_consumer_lag_sum > 10000"
            for   = "5m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "High Kafka consumer lag detected"
              description = "Kafka consumer lag is {{ $value }} for {{ $labels.consumer_group }}"
            }
          },
          {
            alert = "ProcessorDown"
            expr  = "up{job='processor-metrics'} == 0"
            for   = "2m"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "Processor is down"
              description = "Processor {{ $labels.instance }} is down"
            }
          },
          {
            alert = "HighErrorRate"
            expr  = "rate(processor_errors_total[5m]) > 0.1"
            for   = "5m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "High error rate detected"
              description = "Error rate is {{ $value }} errors/sec"
            }
          },
          {
            alert = "LowDiskSpace"
            expr  = "kubelet_volume_stats_available_bytes / kubelet_volume_stats_capacity_bytes < 0.1"
            for   = "5m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "Low disk space"
              description = "Only {{ $value | humanizePercentage }} disk space left on {{ $labels.persistentvolumeclaim }}"
            }
          },
          {
            alert = "NoProcessorSlaves"
            expr  = "kube_deployment_status_replicas{deployment='processor-slaves'} == 0 AND kafka_consumer_lag_sum > 1000"
            for   = "2m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "No processor slaves running with lag"
              description = "Processor slaves scaled to zero but Kafka lag is {{ $value }}"
            }
          }
        ]
      }]
    }
  }
}

# OTEL Collector for trace collection
resource "kubernetes_deployment" "otel_collector" {
  count = var.deploy_k8s_resources && var.enable_otel ? 1 : 0

  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "otel-collector"
      }
    }

    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }

      spec {
        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector-contrib:0.98.0"

          args = ["--config=/etc/otel-collector-config.yaml"]

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          port {
            name           = "otlp-grpc"
            container_port = 4317
          }

          port {
            name           = "otlp-http"
            container_port = 4318
          }

          port {
            name           = "metrics"
            container_port = 8888
          }

          volume_mount {
            name       = "otel-collector-config"
            mount_path = "/etc/otel-collector-config.yaml"
            sub_path   = "otel-collector-config.yaml"
          }
        }

        volume {
          name = "otel-collector-config"
          config_map {
            name = kubernetes_config_map.otel_collector_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# OTEL Collector ConfigMap
resource "kubernetes_config_map" "otel_collector_config" {
  count = var.deploy_k8s_resources && var.enable_otel ? 1 : 0

  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "otel-collector-config.yaml" = yamlencode({
      receivers = {
        otlp = {
          protocols = {
            grpc = {
              endpoint = "0.0.0.0:4317"
            }
            http = {
              endpoint = "0.0.0.0:4318"
            }
          }
        }
      }
      
      processors = {
        batch = {
          timeout = "10s"
          send_batch_size = 1024
        }
        
        resource = {
          attributes = [{
            key    = "environment"
            value  = var.environment
            action = "insert"
          }]
        }
      }
      
      exporters = {
        otlphttp = {
          endpoint = "http://openobserve-service.${var.k8s_namespace}.svc.cluster.local:5080/api/default/v1/traces"
          headers = {
            Authorization = "Basic ${base64encode("admin@example.com:Complexpass#123")}"
          }
        }
        
        logging = {
          loglevel = "info"
        }
      }
      
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["batch", "resource"]
            exporters  = ["otlphttp", "logging"]
          }
        }
      }
    })
  }
}

# Service for OTEL Collector
resource "kubernetes_service" "otel_collector" {
  count = var.deploy_k8s_resources && var.enable_otel ? 1 : 0

  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  spec {
    selector = {
      app = "otel-collector"
    }

    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
    }

    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
    }

    type = "ClusterIP"
  }
}

# Grafana Agent for scraping and remote write
resource "kubernetes_config_map" "grafana_agent_config" {
  count = var.deploy_k8s_resources && var.enable_grafana_agent ? 1 : 0

  metadata {
    name      = "grafana-agent-config"
    namespace = kubernetes_namespace.aurora_logs[0].metadata[0].name
  }

  data = {
    "agent.yaml" = yamlencode({
      server = {
        log_level = "info"
      }
      
      metrics = {
        global = {
          scrape_interval = "30s"
        }
        
        configs = [{
          name = "aurora-logs"
          
          scrape_configs = [{
            job_name = "kubernetes-pods"
            
            kubernetes_sd_configs = [{
              role = "pod"
              namespaces = {
                names = [var.k8s_namespace]
              }
            }]
            
            relabel_configs = [
              {
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                action       = "keep"
                regex        = "true"
              },
              {
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
                action       = "replace"
                target_label = "__metrics_path__"
                regex        = "(.+)"
              }
            ]
          }]
          
          remote_write = [{
            url = "http://openobserve-service.${var.k8s_namespace}.svc.cluster.local:5080/api/default/prometheus/api/v1/write"
            basic_auth = {
              username = "admin@example.com"
              password = "Complexpass#123"
            }
          }]
        }]
      }
      
      logs = {
        configs = [{
          name = "aurora-k8s-logs"
          
          clients = [{
            url = "http://openobserve-service.${var.k8s_namespace}.svc.cluster.local:5080/api/default/loki/api/v1/push"
            basic_auth = {
              username = "admin@example.com"
              password = "Complexpass#123"
            }
          }]
          
          positions = {
            filename = "/tmp/positions.yaml"
          }
          
          scrape_configs = [{
            job_name = "kubernetes-pods"
            
            kubernetes_sd_configs = [{
              role = "pod"
              namespaces = {
                names = [var.k8s_namespace]
              }
            }]
            
            pipeline_stages = [
              {
                docker = {}
              },
              {
                timestamp = {
                  source = "time"
                  format = "RFC3339"
                }
              }
            ]
          }]
        }]
      }
    })
  }
}

# Variables for monitoring features
variable "enable_prometheus" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = false
}

variable "enable_otel" {
  description = "Enable OpenTelemetry collector"
  type        = bool
  default     = true
}

variable "enable_grafana_agent" {
  description = "Enable Grafana Agent for metrics and logs"
  type        = bool
  default     = false
}