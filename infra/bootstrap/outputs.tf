output "aws_account_id" {
  value = local.account_id
}

output "state_bucket" {
  value = module.s3_terraform_state.bucket
}

output "plan_role_arns" {
  value = module.iam_github_plan.role_arns
}

output "apply_role_arns" {
  value = module.iam_github_apply.role_arns
}

output "dns_zone_id" {
  value = module.route53_zone.zone_id
}

output "dns_name_servers" {
  value = module.route53_zone.name_servers
}

output "operator_user_arn" {
  value = module.iam_operator.user_arn
}

output "operator_role_arn" {
  value = module.iam_operator.role_arn
}
