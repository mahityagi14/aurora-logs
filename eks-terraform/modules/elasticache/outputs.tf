output "replication_group_id" {
  description = "ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.valkey.id
}

output "primary_endpoint_address" {
  description = "Address of the primary endpoint for the replication group"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "configuration_endpoint_address" {
  description = "Address of the configuration endpoint for the cluster"
  value       = aws_elasticache_replication_group.valkey.configuration_endpoint_address
}

output "port" {
  description = "Port number for the cache"
  value       = aws_elasticache_replication_group.valkey.port
}

output "security_group_id" {
  description = "Security group ID for the cache cluster"
  value       = aws_security_group.valkey.id
}

output "auth_token_enabled" {
  description = "Whether auth token is enabled"
  value       = aws_elasticache_replication_group.valkey.transit_encryption_enabled
}

output "secret_arn" {
  description = "ARN of the secret containing cache credentials (production only)"
  value       = try(aws_secretsmanager_secret.valkey[0].arn, null)
}