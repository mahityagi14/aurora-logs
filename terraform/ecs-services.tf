# ECS Task Definitions and Services for EC2

# Discovery Service
resource "aws_ecs_task_definition" "discovery" {
  family                   = "${var.name_prefix}-discovery"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn
  cpu                      = tostring(local.container_configs.discovery.cpu)
  memory                   = tostring(local.container_configs.discovery.memory)

  container_definitions = jsonencode([
    {
      name   = "discovery"
      image  = local.container_configs.discovery.image
      cpu    = local.container_configs.discovery.cpu
      memory = local.container_configs.discovery.memory
      
      environment = [
        { name = "AWS_REGION", value = data.aws_region.current.id },
        { name = "INSTANCE_TABLE", value = local.dynamodb_tables.instance_metadata },
        { name = "TRACKING_TABLE", value = local.dynamodb_tables.tracking },
        { name = "JOBS_TABLE", value = local.dynamodb_tables.jobs },
        { name = "S3_BUCKET", value = local.s3_buckets.aurora_logs },
        { name = "KAFKA_BROKERS", value = "kafka.${aws_service_discovery_private_dns_namespace.aurora_logs.name}:9092" },
        { name = "VALKEY_URL", value = "redis://${data.aws_elasticache_replication_group.existing_valkey.primary_endpoint_address}" },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DISCOVERY_INTERVAL_MIN", value = "5" },
        { name = "RATE_LIMIT_PER_SEC", value = "100" },
        { name = "MAX_CONCURRENCY", value = "5" }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        mode      = "non-blocking"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "discovery"
          "awslogs-create-group"  = "true"
          "max-buffer-size"       = "25m"
        }
      }
      
      essential = true
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "discovery" {
  name            = "discovery"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.discovery.arn
  desired_count   = 1  # One task per instance
  launch_type     = "EC2"

  # Ensure this service gets its own dedicated instance
  placement_constraints {
    type = "distinctInstance"
  }

  # Ensure only one task per instance
  placement_constraints {
    type       = "memberOf"
    expression = "task:group == service:discovery"
  }

  tags = local.common_tags
}

# Processor Service
resource "aws_ecs_task_definition" "processor" {
  family                   = "${var.name_prefix}-processor"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn
  cpu                      = tostring(local.container_configs.processor.cpu)
  memory                   = tostring(local.container_configs.processor.memory)

  container_definitions = jsonencode([
    {
      name   = "processor"
      image  = local.container_configs.processor.image
      cpu    = local.container_configs.processor.cpu
      memory = local.container_configs.processor.memory
      
      environment = [
        { name = "AWS_REGION", value = data.aws_region.current.id },
        { name = "INSTANCE_TABLE", value = local.dynamodb_tables.instance_metadata },
        { name = "TRACKING_TABLE", value = local.dynamodb_tables.tracking },
        { name = "JOBS_TABLE", value = local.dynamodb_tables.jobs },
        { name = "S3_BUCKET", value = local.s3_buckets.aurora_logs },
        { name = "KAFKA_BROKERS", value = "kafka.${aws_service_discovery_private_dns_namespace.aurora_logs.name}:9092" },
        { name = "OPENOBSERVE_URL", value = "http://openobserve.${aws_service_discovery_private_dns_namespace.aurora_logs.name}:5080" },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "CONSUMER_GROUP", value = "aurora-processor-group" },
        { name = "SHARD_ID", value = "0" },
        { name = "TOTAL_SHARDS", value = "1" }
      ]
      
      secrets = [
        {
          name      = "OPENOBSERVE_USER"
          valueFrom = "${aws_secretsmanager_secret.openobserve_credentials.arn}:username::"
        },
        {
          name      = "OPENOBSERVE_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.openobserve_credentials.arn}:password::"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        mode      = "non-blocking"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "processor"
          "awslogs-create-group"  = "true"
          "max-buffer-size"       = "25m"
        }
      }
      
      essential = true
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "processor" {
  name            = "processor"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.processor.arn
  desired_count   = 1  # One task per instance
  launch_type     = "EC2"

  # Ensure this service gets its own dedicated instance
  placement_constraints {
    type = "distinctInstance"
  }

  tags = local.common_tags
}

# Kafka Service
resource "aws_ecs_task_definition" "kafka" {
  family                   = "${var.name_prefix}-kafka"
  network_mode             = "host"  # Use host network for Kafka
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn
  cpu                      = tostring(local.container_configs.kafka.cpu)
  memory                   = tostring(local.container_configs.kafka.memory)

  volume {
    name      = "kafka-data"
    host_path = "/mnt/kafka-data"
  }

  container_definitions = jsonencode([
    {
      name   = "kafka"
      image  = local.container_configs.kafka.image
      cpu    = local.container_configs.kafka.cpu
      memory = local.container_configs.kafka.memory
      
      environment = [
        { name = "KAFKA_CFG_NODE_ID", value = "1" },
        { name = "KAFKA_CFG_PROCESS_ROLES", value = "broker,controller" },
        { name = "KAFKA_CFG_CONTROLLER_QUORUM_VOTERS", value = "1@kafka-service:9093" },
        { name = "KAFKA_CFG_LISTENERS", value = "PLAINTEXT://:9092,CONTROLLER://:9093" },
        { name = "KAFKA_CFG_ADVERTISED_LISTENERS", value = "PLAINTEXT://kafka.${aws_service_discovery_private_dns_namespace.aurora_logs.name}:9092" },
        { name = "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP", value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT" },
        { name = "KAFKA_CFG_CONTROLLER_LISTENER_NAMES", value = "CONTROLLER" },
        { name = "KAFKA_CFG_INTER_BROKER_LISTENER_NAME", value = "PLAINTEXT" },
        { name = "KAFKA_ENABLE_KRAFT", value = "yes" },
        { name = "KAFKA_KRAFT_CLUSTER_ID", value = "aurora-logs-kafka-cluster" },
        { name = "KAFKA_CFG_LOG_DIRS", value = "/bitnami/kafka/data" },
        { name = "KAFKA_CFG_METADATA_LOG_DIR", value = "/bitnami/kafka/metadata" },
        { name = "KAFKA_HEAP_OPTS", value = "-Xmx2G -Xms2G" }
      ]
      
      portMappings = [
        {
          containerPort = 9092
          hostPort      = 9092
          protocol      = "tcp"
        },
        {
          containerPort = 9093
          hostPort      = 9093
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "kafka-data"
          containerPath = "/bitnami/kafka/data"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        mode      = "non-blocking"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "kafka"
          "awslogs-create-group"  = "true"
          "max-buffer-size"       = "25m"
        }
      }
      
      essential = true
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "kafka" {
  name            = "kafka"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.kafka.arn
  desired_count   = 1  # One task per instance
  launch_type     = "EC2"

  # Ensure this service gets its own dedicated instance
  placement_constraints {
    type = "distinctInstance"
  }

  tags = local.common_tags
}

# OpenObserve Service
resource "aws_ecs_task_definition" "openobserve" {
  family                   = "${var.name_prefix}-openobserve"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn           = aws_iam_role.ecs_task_role.arn
  cpu                      = tostring(local.container_configs.openobserve.cpu)
  memory                   = tostring(local.container_configs.openobserve.memory)

  volume {
    name      = "openobserve-data"
    host_path = "/mnt/openobserve-data"
  }

  container_definitions = jsonencode([
    {
      name   = "openobserve"
      image  = local.container_configs.openobserve.image
      cpu    = local.container_configs.openobserve.cpu
      memory = local.container_configs.openobserve.memory
      
      environment = [
        { name = "ZO_NODE_ROLE", value = "all" },
        { name = "ZO_LOCAL_MODE", value = "true" },
        { name = "ZO_HTTP_PORT", value = "5080" },
        { name = "ZO_GRPC_PORT", value = "5081" },
        { name = "ZO_DATA_DIR", value = "/data" },
        { name = "ZO_ROOT_USER_EMAIL", value = var.openobserve_admin_email },
        { name = "ZO_S3_BUCKET_NAME", value = local.s3_buckets.k8s_logs },
        { name = "ZO_S3_REGION", value = data.aws_region.current.id }
      ]
      
      secrets = [
        {
          name      = "ZO_ROOT_USER_PASSWORD"
          valueFrom = "${aws_secretsmanager_secret.openobserve_credentials.arn}:password::"
        }
      ]
      
      portMappings = [
        {
          containerPort = 5080
          hostPort      = 5080
          protocol      = "tcp"
        },
        {
          containerPort = 5081
          hostPort      = 5081
          protocol      = "tcp"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "openobserve-data"
          containerPath = "/data"
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        mode      = "non-blocking"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.id
          "awslogs-stream-prefix" = "openobserve"
          "awslogs-create-group"  = "true"
          "max-buffer-size"       = "25m"
        }
      }
      
      essential = true
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "openobserve" {
  name            = "openobserve"
  cluster         = data.aws_ecs_cluster.aurora_logs.id
  task_definition = aws_ecs_task_definition.openobserve.arn
  desired_count   = 1  # One task per instance
  launch_type     = "EC2"

  # Ensure this service gets its own dedicated instance
  placement_constraints {
    type = "distinctInstance"
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.openobserve.arn
    container_name   = "openobserve"
    container_port   = 5080
  }

  depends_on = [aws_lb_listener.openobserve]

  tags = local.common_tags
}