# Aurora Instance Metadata Table
resource "aws_dynamodb_table" "instance_metadata" {
  name         = var.table_names.instance_metadata
  billing_mode = "PAY_PER_REQUEST"  # On-demand pricing
  
  hash_key  = "pk"  # Will store "CLUSTER#cluster-id" or "INSTANCE#instance-id"
  range_key = "sk"  # Will store "METADATA"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # Enable TTL on this table (7-day retention)
  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  # Enable point-in-time recovery for production
  point_in_time_recovery {
    enabled = var.environment == "production" ? true : false
  }

  # Enable deletion protection for production
  deletion_protection_enabled = var.environment == "production" ? true : false

  tags = merge(
    var.tags,
    {
      Name        = var.table_names.instance_metadata
      Purpose     = "Stores RDS cluster and instance metadata"
      TTLEnabled  = "true"
      TTLDays     = "7"
    }
  )
}

# Aurora Log File Tracking Table
resource "aws_dynamodb_table" "tracking" {
  name         = var.table_names.tracking
  billing_mode = "PAY_PER_REQUEST"
  
  hash_key  = "instance_id"
  range_key = "log_file_name"

  attribute {
    name = "instance_id"
    type = "S"
  }

  attribute {
    name = "log_file_name"
    type = "S"
  }

  # NO TTL on this table - processing state must be maintained

  # Enable point-in-time recovery for production
  point_in_time_recovery {
    enabled = var.environment == "production" ? true : false
  }

  # Enable deletion protection for production
  deletion_protection_enabled = var.environment == "production" ? true : false

  tags = merge(
    var.tags,
    {
      Name        = var.table_names.tracking
      Purpose     = "Maintains log file processing state"
      TTLEnabled  = "false"
      Critical    = "true"
    }
  )
}

# Aurora Log Processing Jobs Table
resource "aws_dynamodb_table" "jobs" {
  name         = var.table_names.jobs
  billing_mode = "PAY_PER_REQUEST"
  
  hash_key  = "pk"  # Will store "JOB#job-id" or "DATE#yyyy-mm-dd"
  range_key = "sk"  # Will store "METADATA" or "TIME#hh:mm:ss#job-id"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  # Enable TTL on this table (30-day retention)
  ttl {
    enabled        = true
    attribute_name = "ttl"
  }

  # Enable point-in-time recovery for production
  point_in_time_recovery {
    enabled = var.environment == "production" ? true : false
  }

  # Enable deletion protection for production
  deletion_protection_enabled = var.environment == "production" ? true : false

  tags = merge(
    var.tags,
    {
      Name        = var.table_names.jobs
      Purpose     = "Tracks job history and statistics"
      TTLEnabled  = "true"
      TTLDays     = "30"
    }
  )
}

# CloudWatch alarms for throttling (production only)
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttle" {
  for_each = var.environment == "production" ? toset([
    var.table_names.instance_metadata,
    var.table_names.tracking,
    var.table_names.jobs
  ]) : toset([])

  alarm_name          = "${each.value}-throttle-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "This metric monitors DynamoDB throttling"
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.tags
}