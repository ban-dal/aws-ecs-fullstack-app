# 서비스 연결 역할은 GitHub apply 역할(PowerUserAccess)로 서비스가 필요할 때 만든다. 이미 있는
# 역할은 ECS·Auto Scaling·Client VPN이 쓰고 있어 지우지 않고 state에서만 뺀다. 적용 후 다음
# PR에서 이 블록을 지운다.
removed {
  from = module.iam.aws_iam_service_linked_role.this
  lifecycle { destroy = false }
}

removed {
  from = module.iam.aws_iam_service_linked_role.client_vpn
  lifecycle { destroy = false }
}
