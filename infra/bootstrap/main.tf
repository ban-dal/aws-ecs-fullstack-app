# bootstrap 루트: 계정 단위 기반과 IAM이다. GitHub OIDC 역할 자체를 만들기 때문에
# workflow로 적용할 수 없고, PR merge 후 사람이 scripts/bootstrap.sh로 적용한다.
# 이 파일에는 모듈 호출과 모듈 사이에 넘기는 값만 둔다.

locals {
  environments = toset(["preprod", "prod"])
  account_id   = var.expected_account_id

  github_boundary_name = "aws-fullstack-lab-github-boundary"
  # 운영 역할 정책은 boundary 리소스가 아니라 이름으로 만든 ARN을 쓴다. boundary가
  # 바뀌는 plan에서도 운영 역할 정책 JSON을 읽을 수 있게 하기 위해서다.
  github_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${local.github_boundary_name}"

  budget_name = "aws-fullstack-lab-monthly"

  # 아래 값은 infra/environments/<환경>이 만드는 리소스와 맞아야 한다. ECR 저장소 이름은
  # environments의 ecr-repository 이름과 같고, 로그 그룹은 다른 리소스처럼
  # aws-fullstack-lab-<환경>-으로 시작한다. 읽기 액션은 그 리소스를 refresh할 때 쓴다.
  web_repository_arns = {
    for environment in local.environments :
    environment => "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/aws-fullstack-lab-${environment}-web"
  }

  # 로그 그룹 이름에는 /를 쓰지 않는다. IAM 정책 시뮬레이터가 이름에 /가 든 로그 스트림
  # ARN은 어떤 정책으로도 거부로 판정해서, 정책 테스트가 쓰기 권한을 확인하지 못한다.
  log_group_arns = {
    for environment in local.environments :
    environment => "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:aws-fullstack-lab-${environment}-*"
  }

  # plan 역할의 조회 권한이다. 조회는 리소스를 바꾸지 않으므로 서비스 단위 Describe·List로
  # 준다. provider 버전마다 refresh에 쓰는 조회 API가 달라, 액션을 하나씩 적으면 빠질 때마다
  # root 적용이 필요하다. apply 역할은 서비스 단위로 허용하므로 따로 받지 않는다.
  foundation_read_actions = [
    "autoscaling:Describe*",
    "ec2:Describe*",
    "ecs:Describe*",
    "ecs:List*",
    "logs:Describe*",
    "logs:ListTagsForResource",
    "logs:ListTagsLogGroup",
  ]
}

module "s3_terraform_state" {
  source = "../modules/s3-terraform-state"

  bucket_name = var.state_bucket_name
}

module "iam_github_oidc" {
  source = "../modules/iam-github-oidc"

  boundary_name    = local.github_boundary_name
  environments     = local.environments
  region           = var.aws_region
  state_bucket_arn = module.s3_terraform_state.arn
  passable_role_arns = concat(
    values(module.iam_ecs_roles.host_role_arns),
    values(module.iam_ecs_roles.execution_role_arns),
  )
}

module "iam_github_plan" {
  source = "../modules/iam-github-plan"

  account_id         = local.account_id
  environments       = local.environments
  region             = var.aws_region
  repository_subject = var.github_repository_subject
  oidc_provider_arn  = module.iam_github_oidc.oidc_provider_arn
  boundary_arn       = module.iam_github_oidc.boundary_arn
  state_bucket_arn   = module.s3_terraform_state.arn
  read_actions       = local.foundation_read_actions
  repository_arns    = local.web_repository_arns
}

module "iam_github_apply" {
  source = "../modules/iam-github-apply"

  account_id          = local.account_id
  environments        = local.environments
  region              = var.aws_region
  repository_subject  = var.github_repository_subject
  oidc_provider_arn   = module.iam_github_oidc.oidc_provider_arn
  boundary_arn        = module.iam_github_oidc.boundary_arn
  state_bucket_arn    = module.s3_terraform_state.arn
  repository_arns     = local.web_repository_arns
  host_role_arns      = module.iam_ecs_roles.host_role_arns
  execution_role_arns = module.iam_ecs_roles.execution_role_arns
}

module "iam_github_image" {
  source = "../modules/iam-github-image"

  account_id         = local.account_id
  environments       = local.environments
  region             = var.aws_region
  repository_subject = var.github_repository_subject
  oidc_provider_arn  = module.iam_github_oidc.oidc_provider_arn
  boundary_arn       = module.iam_github_oidc.boundary_arn
  repository_arns    = local.web_repository_arns
}

module "iam_operator" {
  source = "../modules/iam-operator"

  account_id               = local.account_id
  state_bucket_arn         = module.s3_terraform_state.arn
  github_oidc_provider_arn = module.iam_github_oidc.oidc_provider_arn
  github_role_arns = concat(
    values(module.iam_github_plan.role_arns),
    values(module.iam_github_apply.role_arns),
    values(module.iam_github_image.role_arns),
  )
  github_boundary_arn = local.github_boundary_arn
  service_identity_arns = concat(
    values(module.iam_ecs_roles.host_role_arns),
    values(module.iam_ecs_roles.instance_profile_arns),
    values(module.iam_ecs_roles.execution_role_arns),
  )
  budget_name = local.budget_name
}

# ECS 호스트와 태스크가 쓰는 역할이다. GitHub 역할이 아니므로 boundary가 없고, 운영
# 역할은 읽기만 한다.
module "iam_ecs_roles" {
  source = "../modules/iam-ecs-roles"

  account_id      = local.account_id
  environments    = local.environments
  region          = var.aws_region
  repository_arns = local.web_repository_arns
  log_group_arns  = local.log_group_arns
}

module "iam_service_linked_roles" {
  source = "../modules/iam-service-linked-roles"

  service_names = ["autoscaling.amazonaws.com", "ecs.amazonaws.com"]
}

module "budgets" {
  source = "../modules/budgets"

  name        = local.budget_name
  alert_email = var.budget_alert_email
  limit_usd   = var.monthly_budget_usd
}

# prod ALB의 ACM 인증서만 이 영역을 쓴다. preprod는 VPN 안에서 HTTP로 접속하므로
# 인증서가 필요 없다.
module "route53_zone" {
  source = "../modules/route53-zone"

  name        = "aws.bandal.dev"
  caa_issuers = ["amazon.com"]
}

module "ecr_registry" {
  source = "../modules/ecr-registry"

  repository_filter = "aws-fullstack-lab-*"
}
