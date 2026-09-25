# bootstrap 루트: 계정 단위 기반과 IAM이다. PR merge 후 운영자가 scripts/bootstrap.sh로 적용한다.
locals {
  environments = toset(["preprod", "prod"])
  account_id   = var.expected_account_id
}

module "s3_terraform_state" {
  source      = "../modules/s3-terraform-state"
  bucket_name = var.state_bucket_name
}

module "iam" {
  source             = "../modules/iam"
  account_id         = local.account_id
  region             = var.aws_region
  environments       = local.environments
  repository_subject = var.github_repository_subject
  state_bucket_arn   = module.s3_terraform_state.arn
  audit_trail_arn    = module.cloudtrail_audit.trail_arn
  audit_bucket_arn   = module.cloudtrail_audit.bucket_arn
}

module "budgets" {
  source      = "../modules/budgets"
  name        = "aws-fullstack-lab-monthly"
  alert_email = var.alert_email
  limit_usd   = var.monthly_budget_usd
}

module "route53_zone" {
  source      = "../modules/route53-zone"
  name        = "aws.bandal.dev"
  caa_issuers = ["amazon.com"]
}

module "cloudtrail_audit" {
  source      = "../modules/cloudtrail-audit"
  account_id  = local.account_id
  region      = var.aws_region
  trail_name  = "aws-fullstack-lab-audit"
  bucket_name = "${var.state_bucket_name}-audit"
}

module "notifications_root_sign_in" {
  source = "../modules/notifications-root-sign-in"
  count  = var.alert_email == null ? 0 : 1

  email      = var.alert_email
  hub_region = "us-east-1"
  regions    = ["us-east-1", "us-east-2", "us-west-2", var.aws_region]
}

module "ecr_registry" {
  source            = "../modules/ecr-registry"
  repository_filter = "aws-fullstack-lab-*"
}
