# Security groups as per ecs-phases documentation

# Kafka Brokers Security Group
resource "aws_security_group" "kafka_brokers" {
  name        = "kafka-brokers-sg"
  description = "Security group for Kafka brokers on ECS"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_instances.id]
    description = "Kafka client connections"
  }

  ingress {
    from_port   = 9093
    to_port     = 9093
    protocol    = "tcp"
    self        = true
    description = "KRaft controller port"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Inter-broker communication"
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
      Name = "kafka-brokers-sg"
    }
  )
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

# Aurora MySQL Security Group
resource "aws_security_group" "aurora_mysql" {
  name        = "aurora-mysql-sg"
  description = "Security group for Aurora MySQL cluster"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_instances.id]
    description = "Access from ECS"
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Direct access for testing"
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
      Name = "aurora-mysql-sg"
    }
  )
}

# OpenObserve Security Group
resource "aws_security_group" "openobserve" {
  name        = "openobserve-sg"
  description = "Security group for OpenObserve on ECS"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 5080
    to_port     = 5080
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
    description = "HTTP from ALB"
  }

  ingress {
    from_port   = 5080
    to_port     = 5080
    protocol    = "tcp"
    security_groups = [aws_security_group.ecs_instances.id]
    description = "Health checks"
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
      Name = "openobserve-sg"
    }
  )
}