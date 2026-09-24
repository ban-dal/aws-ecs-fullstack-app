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

  # 아래 두 값은 infra/environments가 만드는 리소스와 맞아야 한다. ECR 저장소 이름은
  # environments의 ecr-repository 이름과 같고, 읽기 액션은 그 리소스를 refresh할 때 쓴다.
  web_repository_arns = {
    for environment in local.environments :
    environment => "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/aws-fullstack-lab-${environment}-web"
  }

  foundation_read_actions = [
    "ec2:DescribeAvailabilityZones",
    "ec2:DescribeInternetGateways",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeRouteTables",
    "ec2:DescribeSecurityGroupRules",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeTags",
    "ec2:DescribeVpcAttribute",
    "ec2:DescribeVpcs",
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

module "iam_operator" {
  source = "../modules/iam-operator"

  account_id               = local.account_id
  state_bucket_arn         = module.s3_terraform_state.arn
  github_oidc_provider_arn = module.iam_github_oidc.oidc_provider_arn
  github_role_arns         = concat(values(module.iam_github_plan.role_arns), values(module.iam_github_apply.role_arns))
  github_boundary_arn      = local.github_boundary_arn
  budget_name              = local.budget_name
}

module "budgets" {
  source = "../modules/budgets"

  name        = local.budget_name
  alert_email = var.budget_alert_email
  limit_usd   = var.monthly_budget_usd
}

module "ecr_registry" {
  source = "../modules/ecr-registry"

  repository_filter = "aws-fullstack-lab-*"
}
