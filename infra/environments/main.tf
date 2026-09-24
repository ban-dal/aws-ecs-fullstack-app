# environments 루트: preprod·prod가 같은 구성을 쓰고 environment 변수와 state key만
# 다르다. merge된 main에서 Apply service foundation workflow로 적용한다.
# 이 파일에는 모듈 호출과 환경별 값만 둔다. 루트에 리소스를 직접 두면 적용 workflow
# 검사(scripts/tfplan.sh)가 막는다.

locals {
  name_prefix = "aws-fullstack-lab-${var.environment}"

  vpc_cidrs = {
    preprod = "10.60.0.0/16"
    prod    = "10.61.0.0/16"
  }

  # 태그는 provider default_tags 대신 각 리소스에 명시한다. Environment 태그는 적용
  # 역할의 권한 조건이므로 모든 리소스에 빠짐없이 있어야 한다.
  tags = {
    Project     = "aws-fullstack-lab"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../modules/vpc"

  name_prefix        = local.name_prefix
  cidr_block         = local.vpc_cidrs[var.environment]
  availability_zones = var.availability_zones
  tags               = local.tags
}

module "vpc_security_groups" {
  source = "../modules/vpc-security-groups"

  name_prefix = local.name_prefix
  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = module.vpc.cidr_block
  tags        = local.tags
}

module "ecr_repository" {
  source = "../modules/ecr-repository"

  name = "${local.name_prefix}-web"
  tags = local.tags
}
