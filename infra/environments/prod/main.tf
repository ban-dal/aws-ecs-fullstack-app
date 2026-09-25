# prod 루트: prod 환경의 서비스 리소스다. merge된 main에서 Apply service foundation
# workflow로 적용한다. preprod와 prod는 같은 모듈을 쓰되, 환경마다 필요한 구성과 값이
# 다르므로 루트를 나눈다. 환경별 차이는 docs/architecture.md의 환경과 데이터 경계를 따른다.
# 이 파일에는 모듈 호출과 이 환경의 값만 둔다. 루트에 리소스를 직접 두면 적용
# workflow 검사(scripts/tfplan.sh)가 막는다.

locals {
  environment = "prod"
  name_prefix = "aws-fullstack-lab-${local.environment}"
  # 두 환경의 VPC CIDR은 겹치지 않게 둔다(preprod 10.60.0.0/16, prod 10.61.0.0/16).
  vpc_cidr    = "10.61.0.0/16"
  domain_name = "aws.bandal.dev"

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

  name_prefix         = local.name_prefix
  vpc_id              = module.vpc.vpc_id
  vpc_cidr            = module.vpc.cidr_block
  enable_public_https = true
  tags                = local.tags
}

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  name          = "${local.name_prefix}-web"
  push_role_arn = "arn:aws:iam::${var.expected_account_id}:role/aws-fullstack-lab-app-prod"
  tags          = local.tags
}

module "certificate" {
  source = "../../modules/acm-certificate"

  domain_name = local.domain_name
  tags        = local.tags
}

module "alb" {
  source = "../../modules/alb-web"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = [for az in var.availability_zones : module.vpc.public_subnet_ids[az]]
  security_group_id = module.vpc_security_groups.alb_security_group_id
  certificate_arn   = module.certificate.validated_certificate_arn
  tags              = local.tags
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
  public_subnet_ids  = [for az in var.availability_zones : module.vpc.public_subnet_ids[az]]
  security_group_ids = [module.vpc_security_groups.ecs_host_security_group_id]
  host_count         = 2
  imds_hop_limit     = 2
  tags               = local.tags
}

module "web" {
  source = "../../modules/ecs-prod-web"

  name_prefix    = local.name_prefix
  cluster_id     = module.ecs_cluster.id
  account_id     = var.expected_account_id
  region         = var.aws_region
  repository_url = module.ecr_repository.repository_url
  # Terraform 신규 생성 시 사용하는 seed 이미지. 이후 서비스 revision은 앱 저장소 CI가 관리한다.
  image_tag        = "f98af60d54ad85c79c41bfb2835a25b66d0c833a"
  target_group_arn = module.alb.target_group_arn
  tags             = local.tags

  depends_on = [module.ecs_host, module.alb]
}

module "dns" {
  source = "../../modules/route53-alias"

  # DNS는 ALB 주소에만 의존한다. 웹 서비스까지 묶으면 이미지 교체 때
  # zone data 조회가 apply로 미뤄져 alias 레코드가 불필요하게 교체된다.
  domain_name  = local.domain_name
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}
