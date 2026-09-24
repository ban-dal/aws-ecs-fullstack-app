# 앞으로 둘 ALB와 ECS EC2 호스트의 보안 그룹이다. ALB의 공개 수신은 앱을 켤 때까지
# 닫아 둔다. 호스트는 ALB에서 오는 bridge 동적 포트만 받고 SSH는 열지 않는다.

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

# 규칙에는 태그를 붙이지 않는다. 적용 역할은 Environment 태그가 있는 리소스만 태그를
# 바꿀 수 있고, 규칙 권한은 부모 보안 그룹의 태그로 검사한다.
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

# preprod는 앱 포트를 인터넷에 열지 않는다. WireGuard UDP만 공개하고, HTTP는
# 호스트의 wg0 주소에서 받는다. 별도 SG라 prod의 기존 호스트 SG에는 영향이 없다.
resource "aws_security_group" "wireguard" {
  count       = var.enable_wireguard ? 1 : 0
  name        = "${var.name_prefix}-wireguard"
  description = "WireGuard tunnel ingress for the single preprod host"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name_prefix}-wireguard-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "wireguard" {
  count             = var.enable_wireguard ? 1 : 0
  security_group_id = aws_security_group.wireguard[0].id
  description       = "WireGuard authenticated UDP tunnel"
  ip_protocol       = "udp"
  from_port         = 51820
  to_port           = 51820
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "wireguard" {
  count             = var.enable_wireguard ? 1 : 0
  security_group_id = aws_security_group.wireguard[0].id
  description       = "Host updates and ECS image downloads"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
