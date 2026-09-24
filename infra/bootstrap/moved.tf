# 모듈로 나누기 전의 리소스 주소를 새 주소로 옮긴다. state 안에서만 이동하며 AWS
# 리소스는 바뀌지 않는다. main에서 적용한 뒤 다음 PR에서 이 파일을 지운다.

moved {
  from = aws_s3_bucket.state
  to   = module.s3_terraform_state.aws_s3_bucket.this
}

moved {
  from = aws_s3_bucket_versioning.state
  to   = module.s3_terraform_state.aws_s3_bucket_versioning.this
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.state
  to   = module.s3_terraform_state.aws_s3_bucket_server_side_encryption_configuration.this
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.state
  to   = module.s3_terraform_state.aws_s3_bucket_lifecycle_configuration.this
}

moved {
  from = aws_s3_bucket_public_access_block.state
  to   = module.s3_terraform_state.aws_s3_bucket_public_access_block.this
}

moved {
  from = aws_s3_bucket_policy.state_tls
  to   = module.s3_terraform_state.aws_s3_bucket_policy.this
}

moved {
  from = aws_iam_openid_connect_provider.github
  to   = module.iam_github_oidc.aws_iam_openid_connect_provider.github
}

moved {
  from = aws_iam_policy.github_boundary
  to   = module.iam_github_oidc.aws_iam_policy.boundary
}

moved {
  from = aws_iam_role.plan
  to   = module.iam_github_plan.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.plan
  to   = module.iam_github_plan.aws_iam_role_policy.this
}

moved {
  from = aws_iam_role.foundation_apply
  to   = module.iam_github_apply.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.foundation_apply
  to   = module.iam_github_apply.aws_iam_role_policy.this
}

moved {
  from = aws_iam_user.operator
  to   = module.iam_operator.aws_iam_user.this
}

moved {
  from = aws_iam_user_policy_attachment.operator_login
  to   = module.iam_operator.aws_iam_user_policy_attachment.sign_in
}

moved {
  from = aws_iam_user_policy.operator
  to   = module.iam_operator.aws_iam_user_policy.this
}

moved {
  from = aws_iam_role.operator
  to   = module.iam_operator.aws_iam_role.this
}

moved {
  from = aws_iam_role_policy.operator
  to   = module.iam_operator.aws_iam_role_policy.this
}

moved {
  from = aws_budgets_budget.monthly
  to   = module.budgets.aws_budgets_budget.monthly
}

moved {
  from = aws_ecr_registry_scanning_configuration.main
  to   = module.ecr_registry.aws_ecr_registry_scanning_configuration.this
}
