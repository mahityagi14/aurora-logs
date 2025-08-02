# DB Subnet Group for Aurora
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-aurora-subnet-group"
    }
  )
}

# RDS Cluster Parameter Group
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.name_prefix}-aurora-cluster-pg"
  family      = "aurora-mysql8.0"
  description = "Aurora cluster parameter group for ${var.name_prefix}"

  # Enable slow query log
  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  # Enable general log (only for POC, disable in production)
  parameter {
    name  = "general_log"
    value = var.environment == "poc" ? "1" : "0"
  }

  # Log output to FILE to make logs available via RDS API
  parameter {
    name  = "log_output"
    value = "FILE"
  }

  # Binary log retention (for replication if needed)
  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = var.tags
}

# DB Parameter Group
resource "aws_db_parameter_group" "aurora" {
  name        = "${var.name_prefix}-aurora-db-pg"
  family      = "aurora-mysql8.0"
  description = "Aurora instance parameter group for ${var.name_prefix}"

  tags = var.tags
}

# Security Group for Aurora
resource "aws_security_group" "aurora" {
  name        = "${var.name_prefix}-aurora-sg"
  description = "Security group for Aurora cluster"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from EKS nodes"
    from_port       = 3306
    to_port         = 3306
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
      Name = "${var.name_prefix}-aurora-sg"
    }
  )
}

# Aurora Cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = var.cluster_config.cluster_identifier
  engine                          = "aurora-mysql"
  engine_version                  = var.cluster_config.engine_version
  engine_mode                     = "provisioned"
  database_name                   = var.cluster_config.database_name
  master_username                 = var.cluster_config.master_username
  master_password                 = var.cluster_config.master_password
  
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  
  # Backup configuration
  backup_retention_period         = var.environment == "production" ? 7 : 1
  preferred_backup_window         = "03:00-04:00"
  preferred_maintenance_window    = "sun:04:00-sun:05:00"
  
  # Encryption
  storage_encrypted               = true
  kms_key_id                     = var.kms_key_arn
  
  # Enable logging
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]
  
  # High availability
  availability_zones              = var.availability_zones
  
  # Deletion protection
  deletion_protection             = var.environment == "production" ? true : false
  skip_final_snapshot            = var.environment == "poc" ? true : false
  final_snapshot_identifier      = var.environment == "production" ? "${var.cluster_config.cluster_identifier}-final-${formatdate("YYYY-MM-DD-hhmm", timestamp())}" : null
  
  # Performance Insights
  performance_insights_enabled    = var.environment == "production" ? true : false
  performance_insights_retention_period = var.environment == "production" ? 7 : 0
  
  # Enhanced monitoring
  enable_http_endpoint           = true
  
  tags = merge(
    var.tags,
    {
      Name        = var.cluster_config.cluster_identifier
      Environment = var.environment
    }
  )

  lifecycle {
    prevent_destroy = false  # Change to true for production
  }
}

# Aurora Instances
resource "aws_rds_cluster_instance" "aurora" {
  count = var.cluster_config.instance_count

  identifier                   = "${var.cluster_config.cluster_identifier}-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.aurora.id
  instance_class              = var.cluster_config.instance_class
  engine                      = aws_rds_cluster.aurora.engine
  engine_version              = aws_rds_cluster.aurora.engine_version
  db_parameter_group_name     = aws_db_parameter_group.aurora.name
  
  # Performance insights
  performance_insights_enabled = var.environment == "production" ? true : false
  
  # Enhanced monitoring
  monitoring_interval         = var.environment == "production" ? 60 : 0
  monitoring_role_arn        = var.environment == "production" ? aws_iam_role.rds_monitoring[0].arn : null
  
  # Auto minor version upgrade
  auto_minor_version_upgrade  = var.environment == "poc" ? true : false
  
  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_config.cluster_identifier}-${count.index + 1}"
    }
  )
}

# IAM Role for RDS Enhanced Monitoring (production only)
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "production" ? 1 : 0
  
  name = "${var.name_prefix}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.environment == "production" ? 1 : 0
  
  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# CloudWatch Alarms for Production
resource "aws_cloudwatch_metric_alarm" "database_cpu" {
  count = var.environment == "production" ? var.cluster_config.instance_count : 0

  alarm_name          = "${var.cluster_config.cluster_identifier}-${count.index + 1}-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS CPU utilization"

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.aurora[count.index].id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count = var.environment == "production" ? var.cluster_config.instance_count : 0

  alarm_name          = "${var.cluster_config.cluster_identifier}-${count.index + 1}-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors RDS connection count"

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.aurora[count.index].id
  }

  tags = var.tags
}

# Secret for RDS credentials (production only)
resource "aws_secretsmanager_secret" "aurora" {
  count = var.environment == "production" ? 1 : 0
  
  name = "${var.name_prefix}-aurora-credentials"
  description = "Credentials for Aurora cluster ${var.cluster_config.cluster_identifier}"
  
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "aurora" {
  count = var.environment == "production" ? 1 : 0
  
  secret_id = aws_secretsmanager_secret.aurora[0].id
  secret_string = jsonencode({
    username = var.cluster_config.master_username
    password = var.cluster_config.master_password
    engine   = "mysql"
    host     = aws_rds_cluster.aurora.endpoint
    port     = 3306
    dbname   = var.cluster_config.database_name
  })
}