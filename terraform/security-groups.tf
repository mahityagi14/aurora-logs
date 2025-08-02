# Security groups as per ecs-phases documentation

# Import existing Kafka Brokers Security Group
data "aws_security_group" "kafka_brokers" {
  id = data.aws_security_group.kafka.id  # Using the already imported kafka security group
}

# Valkey Cluster Security Group
resource "aws_security_group" "valkey_cluster" {
  name        = "valkey-cluster-sg"
  description = "Security group for Valkey cache cluster"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_instances.id]
    description = "Redis protocol access"
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
      Name = "valkey-cluster-sg"
    }
  )
}

# Import existing Aurora MySQL Security Group
data "aws_security_group" "aurora_mysql" {
  id = data.aws_security_group.rds.id  # Using the already imported RDS security group
}

# Import existing OpenObserve Security Group
data "aws_security_group" "openobserve_sg" {
  id = data.aws_security_group.openobserve.id  # Using the already imported openobserve security group
}