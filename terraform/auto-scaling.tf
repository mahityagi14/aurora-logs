# Auto Scaling for ECS Services

# Auto Scaling for Processor Service
resource "aws_appautoscaling_target" "processor" {
  max_capacity       = var.environment == "production" ? 10 : 3
  min_capacity       = var.environment == "production" ? 2 : 1
  resource_id        = "service/${data.aws_ecs_cluster.aurora_logs.cluster_name}/${aws_ecs_service.processor.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based scaling policy for Processor
resource "aws_appautoscaling_policy" "processor_cpu" {
  name               = "${var.name_prefix}-processor-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processor.resource_id
  scalable_dimension = aws_appautoscaling_target.processor.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processor.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Memory-based scaling policy for Processor
resource "aws_appautoscaling_policy" "processor_memory" {
  name               = "${var.name_prefix}-processor-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.processor.resource_id
  scalable_dimension = aws_appautoscaling_target.processor.scalable_dimension
  service_namespace  = aws_appautoscaling_target.processor.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value = 80.0
  }
}

# Auto Scaling for Discovery Service (Production only)
resource "aws_appautoscaling_target" "discovery" {
  count = var.environment == "production" ? 1 : 0

  max_capacity       = 5
  min_capacity       = 2
  resource_id        = "service/${data.aws_ecs_cluster.aurora_logs.cluster_name}/${aws_ecs_service.discovery.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "discovery_cpu" {
  count = var.environment == "production" ? 1 : 0

  name               = "${var.name_prefix}-discovery-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.discovery[0].resource_id
  scalable_dimension = aws_appautoscaling_target.discovery[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.discovery[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Scheduled Scaling for POC (Scale down at night)
resource "aws_appautoscaling_scheduled_action" "processor_scale_down" {
  count = var.environment == "poc" ? 1 : 0

  name               = "${var.name_prefix}-processor-scale-down"
  service_namespace  = aws_appautoscaling_target.processor.service_namespace
  resource_id        = aws_appautoscaling_target.processor.resource_id
  scalable_dimension = aws_appautoscaling_target.processor.scalable_dimension

  schedule = "cron(0 20 * * ? *)"  # 8 PM daily

  scalable_target_action {
    min_capacity = 0
    max_capacity = 0
  }
}

resource "aws_appautoscaling_scheduled_action" "processor_scale_up" {
  count = var.environment == "poc" ? 1 : 0

  name               = "${var.name_prefix}-processor-scale-up"
  service_namespace  = aws_appautoscaling_target.processor.service_namespace
  resource_id        = aws_appautoscaling_target.processor.resource_id
  scalable_dimension = aws_appautoscaling_target.processor.scalable_dimension

  schedule = "cron(0 8 * * ? *)"  # 8 AM daily

  scalable_target_action {
    min_capacity = 1
    max_capacity = 3
  }
}