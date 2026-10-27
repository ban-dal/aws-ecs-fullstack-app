# 두 AZ의 공개 ALB가 HTTP를 HTTPS로 전환하고, TLS 종료 후 ECS의 동적 bridge
# 호스트 포트로 전달한다. 대상은 ECS 서비스가 instance ID와 포트로 등록한다.
# ECS blue/green 배포는 두 대상 그룹을 번갈아 쓰고 HTTPS 리스너 규칙의 가중치로 전환한다.
locals {
  # primary는 처음 트래픽을 받는 대상 그룹이다. 배포가 끝날 때마다 두 그룹의 역할이 바뀐다.
  target_groups = {
    primary   = "${var.name_prefix}-web"
    alternate = "${var.name_prefix}-web-alt"
  }
}

resource "aws_lb" "web" {
  name                       = "${var.name_prefix}-web"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = var.public_subnet_ids
  security_groups            = [var.security_group_id]
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_target_group" "web" {
  for_each = local.target_groups

  name                 = each.value
  port                 = 3000
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/api/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web["primary"].arn
  }

  tags = var.tags
}

# ECS가 배포 때 production 리스너 규칙으로 쓰며 가중치를 바꾼다. 모든 요청이 이 규칙에
# 맞으므로 리스너 기본 동작은 쓰이지 않는다.
resource "aws_lb_listener_rule" "web" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 1

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.web["primary"].arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.web["alternate"].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  tags = var.tags

  # 현재 트래픽을 받는 대상 그룹은 ECS 배포가 정한다.
  lifecycle {
    ignore_changes = [action]
  }
}
