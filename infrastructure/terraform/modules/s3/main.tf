# S3 Bucket for Aurora Logs
resource "aws_s3_bucket" "aurora_logs" {
  bucket = var.bucket_names.aurora_logs

  tags = merge(
    var.tags,
    {
      Name        = var.bucket_names.aurora_logs
      Purpose     = "Store processed Aurora logs"
      Environment = var.environment
    }
  )
}

# S3 Bucket for K8s Logs
resource "aws_s3_bucket" "k8s_logs" {
  bucket = var.bucket_names.k8s_logs

  tags = merge(
    var.tags,
    {
      Name        = var.bucket_names.k8s_logs
      Purpose     = "Store Kubernetes pod logs"
      Environment = var.environment
    }
  )
}

# Enable versioning for aurora logs bucket (production only)
resource "aws_s3_bucket_versioning" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id
  
  versioning_configuration {
    status = var.environment == "production" ? "Enabled" : "Disabled"
  }
}

# Enable versioning for k8s logs bucket (production only)
resource "aws_s3_bucket_versioning" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id
  
  versioning_configuration {
    status = var.environment == "production" ? "Enabled" : "Disabled"
  }
}

# Encryption for aurora logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Encryption for k8s logs bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for aurora logs bucket
resource "aws_s3_bucket_public_access_block" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Block public access for k8s logs bucket
resource "aws_s3_bucket_public_access_block" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for aurora logs bucket
resource "aws_s3_bucket_lifecycle_configuration" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.log_retention_days
    }
  }

  rule {
    id     = "delete-incomplete-multipart-uploads"
    status = "Enabled"
    
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Lifecycle policy for k8s logs bucket
resource "aws_s3_bucket_lifecycle_configuration" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    
    filter {}

    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 30  # K8s logs have shorter retention
    }
  }

  rule {
    id     = "delete-incomplete-multipart-uploads"
    status = "Enabled"
    
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# CORS configuration for aurora logs bucket (if needed for web access)
resource "aws_s3_bucket_cors_configuration" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Bucket policy for aurora logs
resource "aws_s3_bucket_policy" "aurora_logs" {
  bucket = aws_s3_bucket.aurora_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.aurora_logs.arn,
          "${aws_s3_bucket.aurora_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Bucket policy for k8s logs
resource "aws_s3_bucket_policy" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.k8s_logs.arn,
          "${aws_s3_bucket.k8s_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# CloudWatch metrics for aurora logs bucket (production only)
resource "aws_s3_bucket_metric" "aurora_logs" {
  count = var.environment == "production" ? 1 : 0
  
  bucket = aws_s3_bucket.aurora_logs.id
  name   = "EntireBucket"
}

# CloudWatch metrics for k8s logs bucket (production only)
resource "aws_s3_bucket_metric" "k8s_logs" {
  count = var.environment == "production" ? 1 : 0
  
  bucket = aws_s3_bucket.k8s_logs.id
  name   = "EntireBucket"
}

# Enable logging for aurora logs bucket (production only)
resource "aws_s3_bucket_logging" "aurora_logs" {
  count = var.environment == "production" ? 1 : 0

  bucket = aws_s3_bucket.aurora_logs.id

  target_bucket = aws_s3_bucket.k8s_logs.id
  target_prefix = "s3-access-logs/aurora-logs/"
}