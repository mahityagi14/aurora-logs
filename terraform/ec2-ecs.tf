# EC2 Configuration for ECS

# Use existing ecs-instance-role from passionate-shark-etprry
data "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
}

# Use existing instance profile
data "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-role"
}

# Security group for ECS instances
resource "aws_security_group" "ecs_instances" {
  name        = "${var.name_prefix}-ecs-instances-sg"
  description = "Security group for ECS container instances"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.existing.cidr_block]
    description = "Allow all traffic from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-ecs-instances-sg"
    }
  )
}

# Launch template for ECS instances
resource "aws_launch_template" "ecs_instances" {
  name_prefix   = "${var.name_prefix}-ecs-"
  image_id      = data.aws_ssm_parameter.ecs_optimized_ami.value
  instance_type = "t4g.medium"  # Fixed to t4g.medium for all environments

  iam_instance_profile {
    name = data.aws_iam_instance_profile.ecs_instance_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  # Configure ECS cluster name
  user_data = base64encode("#!/bin/bash\necho ECS_CLUSTER=gifted-hippopotamus-lcq6xe >> /etc/ecs/ecs.config;")

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${var.name_prefix}-ecs-instance"
        Type = "ecs-container-instance"
      }
    )
  }

  tags = local.common_tags
}

# Get latest ECS optimized AMI for ARM64
data "aws_ssm_parameter" "ecs_optimized_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

# Comment out ASG since we're using existing cluster with instances
# Auto Scaling Group for ECS instances
# Each service gets its own dedicated t4g.medium instance
# resource "aws_autoscaling_group" "ecs_instances" {
#   name                = "${var.name_prefix}-ecs-asg"
#   vpc_zone_identifier = [data.aws_subnet.private_1.id, data.aws_subnet.private_2.id]
#   # 4 services (discovery, processor, kafka, openobserve) = 4 instances minimum
#   min_size            = 4
#   max_size            = 8
#   desired_capacity    = 4
# 
#   launch_template {
#     id      = aws_launch_template.ecs_instances.id
#     version = "$Latest"
#   }
# 
#   tag {
#     key                 = "Name"
#     value               = "${var.name_prefix}-ecs-instance"
#     propagate_at_launch = true
#   }
# 
#   tag {
#     key                 = "AmazonECSManaged"
#     value               = "true"
#     propagate_at_launch = true
#   }
# 
#   dynamic "tag" {
#     for_each = local.common_tags
#     content {
#       key                 = tag.key
#       value               = tag.value
#       propagate_at_launch = true
#     }
#   }
# }

# Comment out capacity provider since we're using existing cluster
# # ECS Capacity Provider
# resource "aws_ecs_capacity_provider" "aurora_logs" {
#   name = "${var.name_prefix}-ec2"
# 
#   auto_scaling_group_provider {
#     auto_scaling_group_arn         = aws_autoscaling_group.ecs_instances.arn
#     managed_termination_protection = "DISABLED"  # Must be disabled without scale-in protection
# 
#     managed_scaling {
#       maximum_scaling_step_size = 1000
#       minimum_scaling_step_size = 1
#       status                    = "ENABLED"
#       target_capacity           = 100
#     }
#   }
# 
#   tags = local.common_tags
# }

# user_data.sh file is managed separately

# Outputs
output "ecs_instance_role_arn" {
  value = data.aws_iam_role.ecs_instance_role.arn
}

# output "ecs_asg_name" {
#   value = aws_autoscaling_group.ecs_instances.name
# }
# 
# output "ecs_capacity_provider_name" {
#   value = aws_ecs_capacity_provider.aurora_logs.name
# }