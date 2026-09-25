# prod 루트: prod 환경의 서비스 리소스다. merge된 main에서 Apply service foundation
# workflow로 적용한다. preprod와 prod는 같은 모듈을 쓰되, 환경마다 필요한 구성과 값이
# 다르므로 루트를 나눈다. 환경별 차이는 docs/architecture.md의 환경과 데이터 경계를 따른다.
# 이 파일에는 모듈 호출과 이 환경의 값만 둔다. 루트에 리소스를 직접 두면 적용
# workflow 검사(scripts/tfplan.sh)가 막는다.

locals {
  environment = "prod"
  name_prefix = "aws-fullstack-lab-${local.environment}"
  # 두 환경의 VPC CIDR은 겹치지 않게 둔다(preprod 10.60.0.0/16, prod 10.61.0.0/16).
  vpc_cidr = "10.61.0.0/16"

  # 태그는 provider default_tags 대신 각 리소스에 명시한다.
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

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = module.vpc.cidr_block
  tags        = local.tags
}

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  name = "${local.name_prefix}-web"
  tags = local.tags
}
