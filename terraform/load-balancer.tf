# Application Load Balancer for OpenObserve

# Security group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.aws_vpc.existing.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
      Name = "${var.name_prefix}-alb-sg"
    }
  )
}

# Application Load Balancer
resource "aws_lb" "openobserve" {
  # ALB is created for both POC and production as per ecs-phases

  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [data.aws_subnet.public_1.id, data.aws_subnet.public_2.id]

  enable_deletion_protection = false
  enable_http2              = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-alb"
    }
  )
}

# Target Group for OpenObserve
resource "aws_lb_target_group" "openobserve" {
  name        = "${var.name_prefix}-openobserve-tg"
  port        = 5080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.existing.id
  target_type = "ip"  # Changed to ip for awsvpc network mode

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/healthz"
    port                = "traffic-port"
    timeout             = 5
    unhealthy_threshold = 2
  }

  stickiness {
    type    = "lb_cookie"
    enabled = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.name_prefix}-openobserve-tg"
    }
  )
}

# ALB Listener
resource "aws_lb_listener" "openobserve" {
  # Listener is created for both POC and production

  load_balancer_arn = aws_lb.openobserve.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.openobserve.arn
  }
}

# Output ALB DNS
output "alb_dns_name" {
  value = aws_lb.openobserve.dns_name
}

# Output OpenObserve access URL
output "openobserve_access" {
  value = "Access OpenObserve via: http://${aws_lb.openobserve.dns_name}"
}