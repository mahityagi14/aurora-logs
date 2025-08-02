output "eks_cluster_role_arn" {
  description = "ARN of the EKS cluster IAM role"
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "ARN of the EKS node group IAM role"
  value       = aws_iam_role.eks_node_group.arn
}

output "jenkins_ecr_user_arn" {
  description = "ARN of the Jenkins ECR user"
  value       = aws_iam_user.jenkins_ecr.arn
}

output "jenkins_ecr_access_key_id" {
  description = "Access key ID for Jenkins ECR user"
  value       = aws_iam_access_key.jenkins_ecr.id
}

output "jenkins_ecr_secret_access_key" {
  description = "Secret access key for Jenkins ECR user"
  value       = aws_iam_access_key.jenkins_ecr.secret
  sensitive   = true
}