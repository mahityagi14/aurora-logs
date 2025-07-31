output "repository_url" {
  description = "The URL of the repository"
  value       = aws_ecr_repository.aurora_log_system.repository_url
}

output "repository_arn" {
  description = "Full ARN of the repository"
  value       = aws_ecr_repository.aurora_log_system.arn
}

output "repository_name" {
  description = "The name of the repository"
  value       = aws_ecr_repository.aurora_log_system.name
}

output "registry_id" {
  description = "The registry ID where the repository was created"
  value       = aws_ecr_repository.aurora_log_system.registry_id
}

output "repository_uri_base" {
  description = "The base URI of the repository (without tag)"
  value       = split(":", aws_ecr_repository.aurora_log_system.repository_url)[0]
}

output "additional_repository_urls" {
  description = "URLs of additional repositories"
  value       = { for k, v in aws_ecr_repository.microservices : k => v.repository_url }
}