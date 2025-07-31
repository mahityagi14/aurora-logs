# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "valkey" {
  name       = "${var.name_prefix}-valkey-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-valkey-subnet-group"
    }
  )
}

# Security Group for Valkey
resource "aws_security_group" "valkey" {
  name        = "${var.name_prefix}-valkey-sg"
  description = "Security group for Valkey cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis protocol from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = var.eks_security_group_ids
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-valkey-sg"
    }
  )
}

# ElastiCache Parameter Group for Valkey 8.0
resource "aws_elasticache_parameter_group" "valkey" {
  family      = "valkey8"
  name        = "${var.name_prefix}-valkey-params"
  description = "Valkey 8.0 parameter group for ${var.name_prefix}"

  # Optimize for caching RDS metadata
  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"  # Evict least recently used keys when memory is full
  }

  parameter {
    name  = "timeout"
    value = "300"  # 5 minutes idle timeout
  }

  # Enable keyspace notifications if needed
  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"  # Expired events and evicted events
  }

  tags = var.tags
}

# ElastiCache Replication Group (Valkey 8.0)
resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = var.cache_config.cluster_id
  description          = "Valkey cluster for caching RDS metadata"
  
  engine               = "valkey"
  engine_version       = var.cache_config.engine_version
  parameter_group_name = aws_elasticache_parameter_group.valkey.name
  port                 = 6379
  
  # Node configuration
  node_type               = var.cache_config.node_type
  num_cache_clusters      = var.cache_config.num_cache_nodes
  
  # Network configuration
  subnet_group_name       = aws_elasticache_subnet_group.valkey.name
  security_group_ids      = [aws_security_group.valkey.id]
  
  # High availability
  automatic_failover_enabled = var.cache_config.num_cache_nodes > 1 ? true : false
  multi_az_enabled          = var.environment == "production" ? true : false
  
  # Backup configuration (production only)
  snapshot_retention_limit   = var.environment == "production" ? 5 : 0
  snapshot_window           = var.environment == "production" ? "03:00-05:00" : null
  
  # Maintenance window
  maintenance_window        = "sun:05:00-sun:06:00"
  
  # Encryption
  at_rest_encryption_enabled = true
  transit_encryption_enabled = var.environment == "production" ? true : false
  # auth_token_enabled is not a valid argument for aws_elasticache_replication_group
  auth_token                = var.environment == "production" ? var.cache_config.auth_token : null
  
  # Notifications
  notification_topic_arn    = var.sns_topic_arn
  
  # Apply changes immediately in POC, during maintenance window in production
  apply_immediately         = var.environment == "poc" ? true : false
  
  # Auto minor version upgrade
  auto_minor_version_upgrade = var.environment == "poc" ? true : false
  
  # Logging disabled per user request
  # log_delivery_configuration {
  #   destination      = aws_cloudwatch_log_group.valkey_slow_log.name
  #   destination_type = "cloudwatch-logs"
  #   log_format       = "json"
  #   log_type         = "slow-log"
  # }
  # 
  # log_delivery_configuration {
  #   destination      = aws_cloudwatch_log_group.valkey_engine_log.name
  #   destination_type = "cloudwatch-logs"
  #   log_format       = "json"
  #   log_type         = "engine-log"
  # }

  tags = merge(
    var.tags,
    {
      Name        = var.cache_config.cluster_id
      Environment = var.environment
    }
  )
  
  # Prevent deletion during terraform destroy
  lifecycle {
    prevent_destroy = true
  }
}

# CloudWatch Log Groups disabled per user request
# resource "aws_cloudwatch_log_group" "valkey_slow_log" {
#   name              = "/aws/elasticache/${var.cache_config.cluster_id}/slow-log"
#   retention_in_days = var.environment == "production" ? 7 : 1
#   
#   tags = var.tags
# }
# 
# resource "aws_cloudwatch_log_group" "valkey_engine_log" {
#   name              = "/aws/elasticache/${var.cache_config.cluster_id}/engine-log"
#   retention_in_days = var.environment == "production" ? 7 : 1
#   
#   tags = var.tags
# }

# CloudWatch Alarms for Production
resource "aws_cloudwatch_metric_alarm" "cache_cpu" {
  count = var.environment == "production" ? 1 : 0

  alarm_name          = "${var.cache_config.cluster_id}-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "This metric monitors ElastiCache CPU utilization"

  dimensions = {
    CacheClusterId = var.cache_config.cluster_id
  }

  alarm_actions = var.sns_alarm_topic_arns

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cache_memory" {
  count = var.environment == "production" ? 1 : 0

  alarm_name          = "${var.cache_config.cluster_id}-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ElastiCache memory usage"

  dimensions = {
    CacheClusterId = var.cache_config.cluster_id
  }

  alarm_actions = var.sns_alarm_topic_arns

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "cache_evictions" {
  count = var.environment == "production" ? 1 : 0

  alarm_name          = "${var.cache_config.cluster_id}-evictions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1000"
  alarm_description   = "This metric monitors ElastiCache evictions"

  dimensions = {
    CacheClusterId = var.cache_config.cluster_id
  }

  alarm_actions = var.sns_alarm_topic_arns

  tags = var.tags
}

# Secret for Valkey auth token (production only)
resource "aws_secretsmanager_secret" "valkey" {
  count = var.environment == "production" ? 1 : 0
  
  name        = "${var.name_prefix}-valkey-auth"
  description = "Auth token for Valkey cluster ${var.cache_config.cluster_id}"
  
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "valkey" {
  count = var.environment == "production" ? 1 : 0
  
  secret_id = aws_secretsmanager_secret.valkey[0].id
  secret_string = jsonencode({
    auth_token = var.cache_config.auth_token
    endpoint   = aws_elasticache_replication_group.valkey.configuration_endpoint_address
    port       = 6379
  })
}