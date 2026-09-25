# ALB와 ECS EC2 호스트의 보안 그룹이다. prod의 ALB만 HTTP 리다이렉트와
# HTTPS를 공개하고, 호스트는 ALB에서 오는 bridge 동적 포트만 받는다. SSH는 열지 않는다.

# 규칙은 inline 블록 대신 별도 규칙 리소스로 관리한다. 이후 ALB 공개 수신 등 규칙을
# 추가할 때 inline 규칙과 규칙 리소스가 서로를 덮어쓰지 않게 하기 위해서다.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Future ALB; public ingress stays closed until the app is enabled"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_security_group" "ecs_host" {
  name        = "${var.name_prefix}-ecs-host"
  description = "Future ECS EC2 host; no SSH or direct public ingress"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-ecs-host-sg" })
}

# 규칙에는 태그를 붙이지 않는다. 환경은 부모 보안 그룹의 태그로 구분한다.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  count             = var.enable_public_https ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "Redirect public HTTP to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count             = var.enable_public_https ? 1 : 0
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_hosts" {
  security_group_id = aws_security_group.alb.id
  description       = "Dynamic ECS host ports inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 32768
  to_port           = 61000
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ecs_host_from_alb" {
  security_group_id            = aws_security_group.ecs_host.id
  description                  = "Dynamic bridge ports from ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 32768
  to_port                      = 61000
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_host_all" {
  security_group_id = aws_security_group.ecs_host.id
  description       = "ECS agent, ECR, and operating system updates"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# AWS Client VPN ENI와 ECS 호스트 사이에는 앱 포트만 허용한다. 인증서로 VPN에
# 들어와도 VPC의 다른 서비스 포트에는 접근할 수 없게 한다.
resource "aws_security_group" "client_vpn" {
  count       = var.enable_client_vpn ? 1 : 0
  name        = "${var.name_prefix}-client-vpn"
  description = "Preprod Client VPN target network"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-client-vpn-sg" })
}

resource "aws_vpc_security_group_egress_rule" "client_vpn_to_web" {
  count                        = var.enable_client_vpn ? 1 : 0
  security_group_id            = aws_security_group.client_vpn[0].id
  description                  = "Only the preprod web host port"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.ecs_host.id
}

resource "aws_vpc_security_group_ingress_rule" "ecs_host_from_client_vpn" {
  count                        = var.enable_client_vpn ? 1 : 0
  security_group_id            = aws_security_group.ecs_host.id
  description                  = "HTTP from authenticated Client VPN sessions"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.client_vpn[0].id
}
