# ECS Task Definitions and Services for EC2

# Discovery Service
resource "aws_ecs_task_definition" "discovery" {
  family                   = "${var.name_prefix}-discovery"
  network_mode             = "awsvpc"
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
        { name = "KAFKA_BROKERS", value = "kafka.aurora-logs.local:9092" },  # Using service discovery DNS
        { name = "VALKEY_PORT", value = "6379" },
        { name = "VALKEY_URL", value = "redis://${data.aws_elasticache_replication_group.existing_valkey.primary_endpoint_address}:6379" },
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "DISCOVERY_INTERVAL_MIN", value = "5" },
        { name = "RATE_LIMIT_PER_SEC", value = "100" },
        { name = "MAX_CONCURRENCY", value = "5" },
        # Cache TTL configurations (in seconds)
        { name = "CACHE_TTL_CLUSTERS", value = "300" },  # 5 minutes
        { name = "CACHE_TTL_INSTANCES", value = "300" }, # 5 minutes  
        { name = "CACHE_TTL_LOGFILES", value = "60" },   # 1 minute
        # DynamoDB TTL configuration (in days)
        { name = "DYNAMODB_TTL_DAYS", value = "7" },
        # Go runtime configuration
        { name = "GOMAXPROCS", value = "2" },
        # Service ports
        { name = "SERVICE_PORT", value = "8080" },
        { name = "HEALTH_CHECK_PORT", value = "8080" },
        # Health check configuration
        { name = "HEALTH_CHECK_INTERVAL", value = "30" },
        { name = "HEALTH_CHECK_TIMEOUT", value = "5" },
        { name = "HEALTH_CHECK_START_PERIOD", value = "30" },
        { name = "HEALTH_CHECK_RETRIES", value = "3" },
        # Container configuration
        { name = "USER_ID", value = "1000" }
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

  # Service Discovery not needed for Discovery service - it doesn't accept incoming connections
  
  # Network configuration for awsvpc mode
  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  depends_on = []

  tags = local.common_tags
}

# Processor Service
resource "aws_ecs_task_definition" "processor" {
  family                   = "${var.name_prefix}-processor"
  network_mode             = "awsvpc"
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
        { name = "KAFKA_BROKERS", value = "kafka.aurora-logs.local:9092" },  # Using service discovery DNS
        { name = "OPENOBSERVE_URL", value = "http://openobserve.aurora-logs.local:5080" },  # Using service discovery DNS
        { name = "LOG_LEVEL", value = "INFO" },
        { name = "CONSUMER_GROUP", value = "aurora-processor-group" },
        { name = "SHARD_ID", value = "0" },
        { name = "TOTAL_SHARDS", value = "1" },
        { name = "MAX_CONCURRENCY", value = "10" },
        { name = "BATCH_SIZE", value = "100" },
        { name = "BATCH_TIMEOUT_SEC", value = "5" },
        # Go runtime configuration
        { name = "GOMAXPROCS", value = "2" },
        # Service ports
        { name = "SERVICE_PORT", value = "8081" },
        { name = "HEALTH_CHECK_PORT", value = "8081" },
        # Health check configuration
        { name = "HEALTH_CHECK_INTERVAL", value = "30" },
        { name = "HEALTH_CHECK_TIMEOUT", value = "5" },
        { name = "HEALTH_CHECK_START_PERIOD", value = "30" },
        { name = "HEALTH_CHECK_RETRIES", value = "3" },
        # Container configuration
        { name = "USER_ID", value = "1000" }
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

  # Service Discovery not needed for Processor service - it doesn't accept incoming connections
  
  # Network configuration for awsvpc mode
  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  depends_on = []

  tags = local.common_tags
}

# Kafka Service
resource "aws_ecs_task_definition" "kafka" {
  family                   = "${var.name_prefix}-kafka"
  network_mode             = "awsvpc"  # Use awsvpc for Service Discovery DNS
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
        { name = "KAFKA_CFG_CONTROLLER_QUORUM_VOTERS", value = "1@localhost:9093" },
        { name = "KAFKA_BROKER_PORT", value = "9092" },
        { name = "KAFKA_CONTROLLER_PORT", value = "9093" },
        { name = "KAFKA_CFG_LISTENERS", value = "PLAINTEXT://:9092,CONTROLLER://:9093" },
        { name = "KAFKA_CFG_ADVERTISED_LISTENERS", value = "PLAINTEXT://kafka.aurora-logs.local:9092" },  # Using service discovery DNS
        { name = "KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP", value = "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT" },
        { name = "KAFKA_CFG_CONTROLLER_LISTENER_NAMES", value = "CONTROLLER" },
        { name = "KAFKA_CFG_INTER_BROKER_LISTENER_NAME", value = "PLAINTEXT" },
        { name = "KAFKA_ENABLE_KRAFT", value = "yes" },
        { name = "KAFKA_KRAFT_CLUSTER_ID", value = "aurora-logs-kafka-cluster" },
        { name = "KAFKA_CFG_LOG_DIRS", value = "/bitnami/kafka/data" },
        { name = "KAFKA_CFG_METADATA_LOG_DIR", value = "/bitnami/kafka/metadata" },
        { name = "KAFKA_HEAP_SIZE", value = "2G" },
        { name = "KAFKA_HEAP_OPTS", value = "-Xmx2G -Xms2G" }
      ]
      
      portMappings = [
        {
          containerPort = 9092
          protocol      = "tcp"
        },
        {
          containerPort = 9093
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

  # Service Discovery configuration
  service_registries {
    registry_arn   = aws_service_discovery_service.kafka.arn
    container_name = "kafka"
    container_port = 9092
  }
  
  # Network configuration for awsvpc mode
  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  depends_on = [aws_service_discovery_service.kafka]

  tags = local.common_tags
}

# OpenObserve Service
resource "aws_ecs_task_definition" "openobserve" {
  family                   = "${var.name_prefix}-openobserve"
  network_mode             = "awsvpc"
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
        { name = "OPENOBSERVE_HTTP_PORT", value = "5080" },
        { name = "OPENOBSERVE_GRPC_PORT", value = "5081" },
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
          protocol      = "tcp"
        },
        {
          containerPort = 5081
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

  # Service Discovery configuration
  service_registries {
    registry_arn   = aws_service_discovery_service.openobserve.arn
    container_name = "openobserve"
    container_port = 5080
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.openobserve.arn
    container_name   = "openobserve"
    container_port   = 5080
  }
  
  # Network configuration for awsvpc mode
  network_configuration {
    subnets         = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
    security_groups = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  depends_on = [aws_lb_listener.openobserve, aws_service_discovery_service.openobserve]

  tags = local.common_tags
}