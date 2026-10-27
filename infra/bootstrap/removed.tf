# 환경별 IAM을 환경 루트로 옮긴다. 역할은 지우지 않고 bootstrap state에서만 뺀 뒤 환경
# 루트의 imports.tf가 가져온다. 두 루트의 적용이 끝나면 다음 PR에서 지운다.
removed {
  from = module.iam.aws_iam_role.github
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.iam.aws_iam_role_policy.github
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.iam.aws_iam_role.ecs_infrastructure
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.iam.aws_iam_role_policy_attachment.ecs_infrastructure
  lifecycle {
    destroy = false
  }
}
