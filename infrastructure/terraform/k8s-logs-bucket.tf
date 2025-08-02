# Only create K8s logs bucket since aurora logs bucket already exists

resource "aws_s3_bucket" "k8s_logs" {
  bucket = local.s3_buckets.k8s_logs
  
  # Allow terraform destroy to delete bucket even if it contains objects
  force_destroy = true

  tags = merge(
    local.common_tags,
    {
      Name        = local.s3_buckets.k8s_logs
      Purpose     = "Store K8s logs"
      Environment = var.environment
    }
  )
}

# Enable versioning
resource "aws_s3_bucket_versioning" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  versioning_configuration {
    status = "Disabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "k8s_logs" {
  bucket = aws_s3_bucket.k8s_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy removed per user request

# Bucket policy
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

output "k8s_logs_bucket_name" {
  value = aws_s3_bucket.k8s_logs.id
}

output "k8s_logs_bucket_arn" {
  value = aws_s3_bucket.k8s_logs.arn
}