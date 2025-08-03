# Terraform outputs for Aurora Log System
# Note: Some outputs are already defined in main.tf and k8s-deployment.tf

# VPC and Network Information (additional)
output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = data.aws_vpc.existing.cidr_block
}

# EKS Cluster Information (additional)
output "eks_cluster_endpoint" {
  description = "Endpoint for EKS cluster"
  value       = data.aws_eks_cluster.existing.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = data.aws_eks_cluster.existing.version
}

# RDS Aurora Information (additional)
output "rds_cluster_reader_endpoint" {
  description = "Reader endpoint for Aurora RDS cluster"
  value       = data.aws_rds_cluster.existing.reader_endpoint
}

# ElastiCache Information (additional)
output "elasticache_port" {
  description = "Port for ElastiCache Valkey cluster"
  value       = module.elasticache.port
}

# S3 Buckets (additional)
output "s3_aurora_logs_bucket_arn" {
  description = "ARN of S3 bucket for Aurora logs"
  value       = data.aws_s3_bucket.existing_aurora_logs.arn
}

output "s3_k8s_logs_bucket_arn" {
  description = "ARN of S3 bucket for Kubernetes logs"
  value       = aws_s3_bucket.k8s_logs.arn
}

# DynamoDB Tables (additional)
output "dynamodb_table_arns" {
  description = "DynamoDB table ARNs"
  value = {
    instance_metadata = data.aws_dynamodb_table.existing_metadata.arn
    tracking         = data.aws_dynamodb_table.existing_tracking.arn
    jobs            = data.aws_dynamodb_table.existing_jobs.arn
  }
}

# Kubernetes Resources (additional)
output "k8s_deployment_status" {
  description = "Status of Kubernetes deployment"
  value       = var.deploy_k8s_resources ? "Kubernetes resources deployed" : "Kubernetes deployment skipped"
}

# Access Information (additional)
output "kafka_access" {
  description = "Kafka broker endpoint within cluster"
  value       = var.deploy_k8s_resources ? "kafka-service.${var.k8s_namespace}.svc.cluster.local:9092" : "Not deployed"
}

# Deployment Commands
output "deployment_commands" {
  description = "Useful commands for managing the deployment"
  value = {
    configure_kubectl  = "aws eks update-kubeconfig --region ${var.region} --name ${data.aws_eks_cluster.existing.name}"
    check_pods        = "kubectl get pods -n ${var.k8s_namespace}"
    check_services    = "kubectl get svc -n ${var.k8s_namespace}"
    view_logs         = "kubectl logs -n ${var.k8s_namespace} -l app=processor --tail=100"
    scale_processors  = "kubectl scale deployment processor-slaves -n ${var.k8s_namespace} --replicas=3"
    port_forward_ui   = "kubectl port-forward -n ${var.k8s_namespace} svc/openobserve-service 5080:5080"
  }
}

# Cost Optimization Status
output "cost_optimization_status" {
  description = "Cost optimization settings"
  value = {
    enabled              = var.enable_cost_optimization
    fargate_enabled      = var.enable_fargate
    estimated_monthly    = var.enable_cost_optimization ? "$60-80" : "$200-300"
    scale_to_zero       = var.enable_cost_optimization ? "Enabled for processor slaves" : "Disabled"
  }
}

# Monitoring Status
output "monitoring_status" {
  description = "Monitoring and observability status"
  value = {
    prometheus_enabled    = var.enable_prometheus
    otel_enabled         = var.enable_otel
    grafana_agent_enabled = var.enable_grafana_agent
    k8s_logs_to_s3       = var.deploy_k8s_resources ? "Enabled via Fluent Bit" : "Not configured"
  }
}

# Next Steps
output "next_steps" {
  description = "Recommended next steps after deployment"
  value = var.deploy_k8s_resources ? [
    "1. Configure kubectl: ${data.aws_eks_cluster.existing.name}",
    "2. Verify pods are running: kubectl get pods -n ${var.k8s_namespace}",
    "3. Access OpenObserve UI: kubectl port-forward -n ${var.k8s_namespace} svc/openobserve-service 5080:5080",
    "4. Configure Aurora RDS to export logs to CloudWatch",
    "5. Monitor Kafka lag and processor performance",
    var.enable_cost_optimization ? "6. Review scale-to-zero behavior for cost optimization" : "6. Monitor resource utilization"
  ] : [
    "Kubernetes resources not deployed. Set deploy_k8s_resources = true to deploy."
  ]
}