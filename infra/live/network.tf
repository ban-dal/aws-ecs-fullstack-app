resource "aws_vpc" "app" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "app" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.name_prefix}-public-${each.key}" })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.app.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(local.tags, { Name = "${local.name_prefix}-private-${each.key}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.app.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.app.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# 규칙은 inline 블록 대신 별도 규칙 리소스로 관리한다. 이후 ALB 공개 수신 등 규칙을
# 추가할 때 inline 규칙과 규칙 리소스가 서로를 덮어쓰지 않게 하기 위해서다.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Future ALB; public ingress stays closed until the app is enabled"
  vpc_id      = aws_vpc.app.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-sg" })
}

resource "aws_security_group" "ecs_host" {
  name        = "${local.name_prefix}-ecs-host"
  description = "Future ECS EC2 host; no SSH or direct public ingress"
  vpc_id      = aws_vpc.app.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-ecs-host-sg" })
}

# 규칙에는 태그를 붙이지 않는다. 적용 역할은 Environment 태그가 있는 리소스만 태그를
# 바꿀 수 있고, 규칙 권한은 부모 보안 그룹의 태그로 검사한다.
resource "aws_vpc_security_group_egress_rule" "alb_to_hosts" {
  security_group_id = aws_security_group.alb.id
  description       = "Dynamic ECS host ports inside the VPC"
  ip_protocol       = "tcp"
  from_port         = 32768
  to_port           = 61000
  cidr_ipv4         = local.vpc_cidr
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
