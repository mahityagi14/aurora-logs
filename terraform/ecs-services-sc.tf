# ECS Task Definitions and Services with Service Connect

# Update Discovery Service with Service Connect
resource "aws_ecs_service" "discovery_sc" {
  count = var.enable_service_connect ? 1 : 0
  
  name            = "discovery"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.discovery.arn
  desired_count   = 1
  launch_type     = "EC2"

  placement_constraints {
    type = "distinctInstance"
  }

  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Service Connect configuration as client only
  service_connect_configuration {
    enabled = true
    namespace = aws_service_discovery_http_namespace.aurora_logs_sc.arn
  }

  depends_on = [aws_service_discovery_http_namespace.aurora_logs_sc]
  
  tags = local.common_tags
}

# Update Processor Service with Service Connect
resource "aws_ecs_service" "processor_sc" {
  count = var.enable_service_connect ? 1 : 0
  
  name            = "processor"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.processor.arn
  desired_count   = 1
  launch_type     = "EC2"

  placement_constraints {
    type = "distinctInstance"
  }

  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Service Connect configuration as client only
  service_connect_configuration {
    enabled = true
    namespace = aws_service_discovery_http_namespace.aurora_logs_sc.arn
  }

  depends_on = [aws_service_discovery_http_namespace.aurora_logs_sc]
  
  tags = local.common_tags
}

# Update Kafka Service with Service Connect
resource "aws_ecs_service" "kafka_sc" {
  count = var.enable_service_connect ? 1 : 0
  
  name            = "kafka"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.kafka.arn
  desired_count   = 1
  launch_type     = "EC2"

  placement_constraints {
    type = "distinctInstance"
  }

  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Service Connect configuration as server
  service_connect_configuration {
    enabled = true
    namespace = aws_service_discovery_http_namespace.aurora_logs_sc.arn
    
    service {
      port_name      = "kafka"
      discovery_name = "kafka"
      client_alias {
        port     = 9092
        dns_name = "kafka"
      }
    }
  }

  depends_on = [aws_service_discovery_http_namespace.aurora_logs_sc]
  
  tags = local.common_tags
}

# Update OpenObserve Service with Service Connect
resource "aws_ecs_service" "openobserve_sc" {
  count = var.enable_service_connect ? 1 : 0
  
  name            = "openobserve"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.openobserve.arn
  desired_count   = 1
  launch_type     = "EC2"

  placement_constraints {
    type = "distinctInstance"
  }

  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  # Service Connect configuration as server
  service_connect_configuration {
    enabled = true
    namespace = aws_service_discovery_http_namespace.aurora_logs_sc.arn
    
    service {
      port_name      = "openobserve"
      discovery_name = "openobserve"
      client_alias {
        port     = 5080
        dns_name = "openobserve"
      }
    }
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.openobserve.arn
    container_name   = "openobserve"
    container_port   = 5080
  }

  depends_on = [
    aws_lb_listener.openobserve,
    aws_service_discovery_http_namespace.aurora_logs_sc
  ]
  
  tags = local.common_tags
}