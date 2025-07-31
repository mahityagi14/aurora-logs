# ECR Repository for Aurora Log System
resource "aws_ecr_repository" "aurora_log_system" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  # Enable image scanning on push
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  # Encryption configuration
  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key        = var.kms_key_arn
  }

  tags = merge(
    var.tags,
    {
      Name        = var.repository_name
      Environment = var.environment
    }
  )
}

# Lifecycle policy to manage image retention
resource "aws_ecr_lifecycle_policy" "aurora_log_system" {
  repository = aws_ecr_repository.aurora_log_system.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.untagged_image_retention_days} untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_retention_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_image_count} tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "release"]
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 3
        description  = "Keep production images forever"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["production", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 999999  # Effectively keep forever
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 4
        description  = "Remove old development images after ${var.dev_image_retention_days} days"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev", "development", "feature"]
          countType     = "sinceImagePushed"
          countUnit     = "days"
          countNumber   = var.dev_image_retention_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Repository policy to control access
resource "aws_ecr_repository_policy" "aurora_log_system" {
  repository = aws_ecr_repository.aurora_log_system.name

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Sid    = "AllowPull"
        Effect = "Allow"
        Principal = {
          AWS = concat(
            var.pull_principal_arns,
            [data.aws_caller_identity.current.account_id]
          )
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages"
        ]
      },
      {
        Sid    = "AllowPush"
        Effect = "Allow"
        Principal = {
          AWS = concat(
            var.push_principal_arns,
            [data.aws_caller_identity.current.account_id]
          )
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListImages",
          "ecr:DeleteRepository",
          "ecr:BatchDeleteImage",
          "ecr:SetRepositoryPolicy",
          "ecr:DeleteRepositoryPolicy"
        ]
      }
    ]
  })
}

# CloudWatch metric alarm for repository size (production only)
resource "aws_cloudwatch_metric_alarm" "repository_size" {
  count = var.environment == "production" ? 1 : 0

  alarm_name          = "${var.repository_name}-size-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "RepositorySize"
  namespace           = "AWS/ECR"
  period              = "300"
  statistic           = "Average"
  threshold           = var.repository_size_alarm_threshold
  alarm_description   = "This metric monitors ECR repository size"
  treat_missing_data  = "notBreaching"

  dimensions = {
    RepositoryName = aws_ecr_repository.aurora_log_system.name
  }

  alarm_actions = var.alarm_sns_topic_arns

  tags = var.tags
}

# Data source for current account
data "aws_caller_identity" "current" {}

# Additional repositories for microservices (if needed)
resource "aws_ecr_repository" "microservices" {
  for_each = toset(var.additional_repositories)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  encryption_configuration {
    encryption_type = var.encryption_type
    kms_key        = var.kms_key_arn
  }

  tags = merge(
    var.tags,
    {
      Name        = each.value
      Environment = var.environment
      Component   = "microservice"
    }
  )
}

# Apply same lifecycle policy to additional repositories
resource "aws_ecr_lifecycle_policy" "microservices" {
  for_each = toset(var.additional_repositories)

  repository = aws_ecr_repository.microservices[each.key].name
  policy     = aws_ecr_lifecycle_policy.aurora_log_system.policy
}