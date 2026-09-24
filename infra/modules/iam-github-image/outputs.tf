# 역할 이름으로 ARN을 만든다. 운영 역할의 Deny가 역할을 지웠다 다시 만든 경우에도
# 적용되고, 역할이 생기기 전에도 plan에서 정책 JSON을 읽을 수 있다.
output "role_arns" {
  value = { for environment, name in local.role_names : environment => "arn:aws:iam::${var.account_id}:role/${name}" }
}
