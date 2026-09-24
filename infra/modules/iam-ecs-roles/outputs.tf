# 역할 이름으로 ARN을 만든다. 역할이 생기기 전에도 plan에서 boundary와 apply 역할 정책
# JSON을 읽을 수 있게 하기 위해서다.
output "host_role_arns" {
  value = { for environment, name in local.host_role_names : environment => "arn:aws:iam::${var.account_id}:role/${name}" }
}

output "instance_profile_arns" {
  value = { for environment, name in local.host_role_names : environment => "arn:aws:iam::${var.account_id}:instance-profile/${name}" }
}

output "execution_role_arns" {
  value = { for environment, name in local.execution_role_names : environment => "arn:aws:iam::${var.account_id}:role/${name}" }
}
