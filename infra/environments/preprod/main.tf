# preprod 루트: preprod 환경의 서비스 리소스다. merge된 main에서 Apply service foundation
# workflow로 적용한다. preprod와 prod는 같은 모듈을 쓰되, 환경마다 필요한 구성과 값이
# 다르므로 루트를 나눈다. 환경별 차이는 docs/architecture.md의 환경과 데이터 경계를 따른다.
# 이 파일에는 모듈 호출과 이 환경의 값만 둔다. 루트에 리소스를 직접 두면 적용
# workflow 검사(scripts/tfplan.sh)가 막는다.

locals {
  environment = "preprod"
  name_prefix = "aws-fullstack-lab-${local.environment}"
  # 두 환경의 VPC CIDR은 겹치지 않게 둔다(preprod 10.60.0.0/16, prod 10.61.0.0/16).
  vpc_cidr = "10.60.0.0/16"

  # 태그는 provider default_tags 대신 각 리소스에 명시한다. 두 환경이 한 계정을 쓰므로
  # 콘솔과 비용에서 Environment 태그로 환경을 구분한다.
  tags = {
    Project     = "aws-fullstack-lab"
    Environment = local.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name_prefix        = local.name_prefix
  cidr_block         = local.vpc_cidr
  availability_zones = var.availability_zones
  tags               = local.tags
}

module "vpc_security_groups" {
  source = "../../modules/vpc-security-groups"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.cidr_block
  enable_client_vpn = true
  tags              = local.tags
}

module "client_vpn" {
  source = "../../modules/ec2-client-vpn"

  name_prefix            = local.name_prefix
  vpc_id                 = module.vpc.vpc_id
  vpc_cidr               = module.vpc.cidr_block
  subnet_id              = module.vpc.public_subnet_ids[var.availability_zones[0]]
  security_group_id      = module.vpc_security_groups.client_vpn_security_group_id
  server_certificate_arn = var.client_vpn_server_certificate_arn
  tags                   = local.tags
}

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  name          = "${local.name_prefix}-web"
  push_role_arn = "arn:aws:iam::${var.expected_account_id}:role/aws-fullstack-lab-app-preprod"
  tags          = local.tags
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name_prefix = local.name_prefix
  tags        = local.tags
}

module "ecs_host" {
  source = "../../modules/ec2-ecs-host"

  name_prefix        = local.name_prefix
  cluster_name       = module.ecs_cluster.name
  public_subnet_id   = module.vpc.public_subnet_ids[var.availability_zones[0]]
  security_group_ids = [module.vpc_security_groups.ecs_host_security_group_id]
  tags               = local.tags
}

module "web" {
  source = "../../modules/ecs-preprod-web"

  name_prefix    = local.name_prefix
  cluster_id     = module.ecs_cluster.id
  account_id     = var.expected_account_id
  region         = var.aws_region
  repository_url = module.ecr_repository.repository_url
  # Terraform 신규 생성 시 사용하는 seed 이미지. 이후 서비스 revision은 앱 저장소 CI가 관리한다.
  image_tag = "757ff359a5bb83c9b5dab18767d5d80f8e876db4"
  tags      = local.tags

  depends_on = [module.ecs_host]
}
