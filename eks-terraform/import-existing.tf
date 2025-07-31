# Import existing S3 bucket for aurora logs
data "aws_s3_bucket" "existing_aurora_logs" {
  bucket = "company-aurora-logs-poc"
}

# Import existing DynamoDB tables
data "aws_dynamodb_table" "existing_metadata" {
  name = "aurora-instance-metadata"
}

data "aws_dynamodb_table" "existing_tracking" {
  name = "aurora-log-file-tracking"
}

data "aws_dynamodb_table" "existing_jobs" {
  name = "aurora-log-processing-jobs"
}

# Import existing ECR repository
data "aws_ecr_repository" "existing_aurora_log_system" {
  name = "aurora-log-system"
}