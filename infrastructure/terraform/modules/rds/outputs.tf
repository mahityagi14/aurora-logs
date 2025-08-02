output "cluster_id" {
  description = "The RDS cluster identifier"
  value       = aws_rds_cluster.aurora.id
}

output "cluster_endpoint" {
  description = "The cluster endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "The cluster reader endpoint"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "cluster_port" {
  description = "The database port"
  value       = aws_rds_cluster.aurora.port
}

output "database_name" {
  description = "The database name"
  value       = aws_rds_cluster.aurora.database_name
}

output "security_group_id" {
  description = "Security group ID for the RDS cluster"
  value       = aws_security_group.aurora.id
}

output "instance_identifiers" {
  description = "List of instance identifiers"
  value       = [for instance in aws_rds_cluster_instance.aurora : instance.id]
}

output "secret_arn" {
  description = "ARN of the secret containing database credentials (production only)"
  value       = try(aws_secretsmanager_secret.aurora[0].arn, null)
}