# Service Discovery for ECS Services

# Create a private DNS namespace
resource "aws_service_discovery_private_dns_namespace" "aurora_logs" {
  name        = "aurora-logs.local"
  description = "Private DNS namespace for Aurora Log System"
  vpc         = data.aws_vpc.existing.id

  tags = local.common_tags
}

# Service Discovery for Discovery Service
resource "aws_service_discovery_service" "discovery" {
  name = "discovery"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aurora_logs.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    # failure_threshold is deprecated and always set to 1 by AWS
  }

  tags = local.common_tags
}

# Service Discovery for Processor Service
resource "aws_service_discovery_service" "processor" {
  name = "processor"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aurora_logs.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    # failure_threshold is deprecated and always set to 1 by AWS
  }

  tags = local.common_tags
}

# Service Discovery for Kafka
resource "aws_service_discovery_service" "kafka" {
  name = "kafka"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aurora_logs.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "WEIGHTED"
  }

  health_check_custom_config {
    # failure_threshold is deprecated and always set to 1 by AWS
  }

  tags = local.common_tags
}

# Service Discovery for OpenObserve
resource "aws_service_discovery_service" "openobserve" {
  name = "openobserve"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.aurora_logs.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "WEIGHTED"
  }

  health_check_custom_config {
    # failure_threshold is deprecated and always set to 1 by AWS
  }

  tags = local.common_tags
}