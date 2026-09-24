# preprod 앱은 ALB 없이 호스트 한 대의 고정 3000 포트에서 실행한다. 교체 배포는
# 같은 포트를 동시에 쓸 수 없으므로 기존 태스크를 먼저 내려야 한다.
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
      hostPort      = 3000
      protocol      = "tcp"
    }]
    environment = [{ name = "APP_ENV", value = "preprod" }]
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
}

resource "aws_ecs_service" "web" {
  name                               = "web"
  cluster                            = var.cluster_id
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = 1
  launch_type                        = "EC2"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = var.tags
}
