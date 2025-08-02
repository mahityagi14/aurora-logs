output "aurora_logs_bucket_name" {
  description = "Name of the Aurora logs S3 bucket"
  value       = aws_s3_bucket.aurora_logs.id
}

output "aurora_logs_bucket_arn" {
  description = "ARN of the Aurora logs S3 bucket"
  value       = aws_s3_bucket.aurora_logs.arn
}

output "k8s_logs_bucket_name" {
  description = "Name of the K8s logs S3 bucket"
  value       = aws_s3_bucket.k8s_logs.id
}

output "k8s_logs_bucket_arn" {
  description = "ARN of the K8s logs S3 bucket"
  value       = aws_s3_bucket.k8s_logs.arn
}