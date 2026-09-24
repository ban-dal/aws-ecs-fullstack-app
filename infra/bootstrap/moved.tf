# 기존 OIDC 제공자와 사람의 로그인 정보를 유지한다. 적용 후 다음 PR에서 제거한다.
moved {
  from = module.iam_github_oidc.aws_iam_openid_connect_provider.github
  to   = module.iam.aws_iam_openid_connect_provider.github
}

moved {
  from = module.iam_operator.aws_iam_user.this
  to   = module.iam.aws_iam_user.operator
}

moved {
  from = module.iam_operator.aws_iam_role.this
  to   = module.iam.aws_iam_role.operator
}

moved {
  from = module.iam_service_linked_roles.aws_iam_service_linked_role.this["autoscaling.amazonaws.com"]
  to   = module.iam.aws_iam_service_linked_role.this["autoscaling.amazonaws.com"]
}

moved {
  from = module.iam_service_linked_roles.aws_iam_service_linked_role.this["ecs.amazonaws.com"]
  to   = module.iam.aws_iam_service_linked_role.this["ecs.amazonaws.com"]
}
