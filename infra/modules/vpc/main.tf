# 환경별 VPC와 두 가용 영역의 공개·비공개 서브넷, 라우팅이다. NAT Gateway는 비용 때문에
# 두지 않는다. 공개 라우트만 Internet Gateway로 나가고, 비공개 서브넷에는 인터넷 경로가
# 없다. 공개 서브넷도 퍼블릭 IP 자동 할당을 끈다. 퍼블릭 IP가 필요한 리소스는 비용을
# 검토한 뒤 명시적으로 할당한다.
#
# 서브넷은 AZ를 키로 만들고 CIDR은 AZ 순서로 정한다. 적용 후 AZ 순서를 바꾸면 서브넷이
# 교체된다.

locals {
  public_subnets = {
    for index, az in var.availability_zones : az => cidrsubnet(var.cidr_block, 8, index)
  }
  private_subnets = {
    for index, az in var.availability_zones : az => cidrsubnet(var.cidr_block, 8, index + 10)
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-public-${each.key}" })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-${each.key}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
