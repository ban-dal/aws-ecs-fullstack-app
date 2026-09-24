output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

# 역할이 boundary보다 먼저 만들어지지 않도록 리소스 속성으로 넘긴다.
output "boundary_arn" {
  value = aws_iam_policy.boundary.arn
}
