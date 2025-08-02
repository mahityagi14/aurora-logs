# ECS Service Connect Configuration

# Create Service Connect namespace
resource "aws_service_discovery_http_namespace" "aurora_logs_sc" {
  name        = "aurora-logs-sc"
  description = "Service Connect namespace for Aurora Log System"
  
  tags = local.common_tags
}

# Update cluster to enable Service Connect
resource "aws_ecs_cluster_capacity_providers" "aurora_logs" {
  cluster_name = data.aws_ecs_cluster.aurora_logs.cluster_name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 0
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Service Connect configuration for each service
locals {
  service_connect_config = {
    kafka = {
      port_name = "kafka"
      discovery_name = "kafka"
      dns_name = "kafka.aurora-logs-sc.local"
      port = 9092
    }
    openobserve = {
      port_name = "openobserve"
      discovery_name = "openobserve" 
      dns_name = "openobserve.aurora-logs-sc.local"
      port = 5080
    }
  }
}