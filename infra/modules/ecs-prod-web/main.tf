# prod는 두 AZ의 ECS 호스트에 태스크 두 개를 분산한다. bridge 동적 포트를
# ALB 대상 그룹에 등록하고 헬스 체크 실패나 앱 5xx 증가 시 배포를 되돌린다.
# 배포는 blue/green이다. 새 태스크 두 개를 대기 대상 그룹에 띄운 뒤 트래픽을 한 번에
# 옮기므로, 배포 중 한 사용자의 요청이 두 버전에 섞여 들어가지 않는다.
resource "aws_cloudwatch_log_group" "web" {
  name              = "${var.name_prefix}-web"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${var.name_prefix}-web"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-task-execution"

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "web"
    image     = "${var.repository_url}:${var.image_tag}"
    essential = true
    portMappings = [{
      containerPort = 3000
      hostPort      = 0
      protocol      = "tcp"
    }]
    environment = [{ name = "APP_ENV", value = "prod" }]
    healthCheck = {
      command     = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.web.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "web"
      }
    }
  }])

  tags = var.tags

  # 새 revision을 등록하고 서비스가 그 revision으로 전환한 뒤 기존 revision을 해제한다.
  lifecycle {
    create_before_destroy = true
  }
}

# health는 정상인데 다른 경로가 5xx를 내는 배포를 잡는다. ECS는 배포 중과 배포 직후
# 이 alarm이 ALARM이 되면 이전 revision으로 되돌린다. 요청이 없으면 울리지 않는다.
# 배포마다 트래픽을 받는 대상 그룹이 바뀌므로 ALB 전체 대상 5xx를 본다.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.name_prefix}-web-target-5xx"
  alarm_description   = "prod 앱 5xx 증가. ECS 배포 alarm 롤백에 쓴다."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  tags = var.tags
}

# blue/green은 배포 중 기존 두 태스크 옆에 새 두 태스크를 띄우므로 호스트 한 대에 태스크가
# 두 개 놓인다. 그래서 distinctInstance 대신 AZ spread로 나누고, 배포가 끝난 뒤 서로 다른
# EC2 두 대에 있는지는 앱 배포 스크립트와 scripts/prod-service.sh check가 확인한다.
# bake time 동안 이전 태스크를 남겨 alarm이 울리면 트래픽만 되돌린다.
# AZ rebalancing은 배포 밖에서 태스크를 옮기므로 끈다.
resource "aws_ecs_service" "web" {
  name                               = "web"
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = 2
  launch_type                        = "EC2"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  wait_for_steady_state              = true
  health_check_grace_period_seconds  = 120
  availability_zone_rebalancing      = "DISABLED"

  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = 5
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  alarms {
    alarm_names = [aws_cloudwatch_metric_alarm.target_5xx.alarm_name]
    enable      = true
    rollback    = true
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "web"
    container_port   = 3000

    advanced_configuration {
      alternate_target_group_arn = var.alternate_target_group_arn
      production_listener_rule   = var.production_listener_rule_arn
      # modules/iam의 ECS 인프라 역할이다. bootstrap을 먼저 적용한다.
      role_arn = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-infrastructure"
    }
  }

  tags = var.tags

  # 앱 저장소 workflow가 active revision을 바꾼다. 기반 apply에서 이를 되돌리지 않는다.
  lifecycle {
    ignore_changes = [task_definition]
  }
}
