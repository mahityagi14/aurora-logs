# Secrets Manager for sensitive data

# OpenObserve credentials
resource "aws_secretsmanager_secret" "openobserve_credentials" {
  name        = "${var.name_prefix}-openobserve-credentials"
  description = "Credentials for OpenObserve admin user"

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "openobserve_credentials" {
  secret_id = aws_secretsmanager_secret.openobserve_credentials.id
  
  secret_string = jsonencode({
    username = "admin@example.com"
    password = random_password.openobserve_password.result
  })
}

# Generate random password for OpenObserve
resource "random_password" "openobserve_password" {
  length  = 16
  special = true
}

# Output the secret ARN for use in task definitions
output "openobserve_secret_arn" {
  value = aws_secretsmanager_secret.openobserve_credentials.arn
}

# Note: To retrieve the password after creation:
# aws secretsmanager get-secret-value --secret-id <secret-name> --query SecretString --output text | jq -r .password