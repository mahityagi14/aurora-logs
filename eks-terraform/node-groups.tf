# EKS Node Groups for Aurora Log System

# Create the node groups using the existing EKS cluster
resource "aws_eks_node_group" "aurora_logs" {
  cluster_name    = data.aws_eks_cluster.existing.name
  node_group_name = "${var.name_prefix}-node-group"
  node_role_arn   = data.aws_iam_role.eks_node.arn
  subnet_ids      = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
  
  # Use larger t4g.xlarge ARM64 instance to run all services
  instance_types = ["t4g.xlarge"]  # 4 vCPUs, 16 GB RAM
  
  # Specify ARM64 AMI type for Graviton instances
  ami_type = "AL2023_ARM_64_STANDARD"
  
  scaling_config {
    desired_size = 1  # Single large node to run all services
    max_size     = 2  # Allow scaling to 2 for high availability
    min_size     = 1  # Minimum 1 node
  }
  
  # Configure the nodes with proper labels
  labels = {
    Environment = var.environment
    Project     = "aurora-log-system"
    NodeType    = "application"
  }
  
  # Let EKS manage the instance configuration
  # No custom launch template needed for managed node groups
  
  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-eks-node-group"
      Type = "application"
    }
  )
  
  # Ensure proper dependencies
  depends_on = [
    data.aws_iam_role.eks_node
  ]
}

# Output node group information
output "node_group_id" {
  value = aws_eks_node_group.aurora_logs.id
}

output "node_group_status" {
  value = aws_eks_node_group.aurora_logs.status
}