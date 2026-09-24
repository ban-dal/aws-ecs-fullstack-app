# preprod에 inline 블록으로 만들었던 보안 그룹 규칙을 별도 규칙 리소스로 가져온다.
# 새로 만들면 같은 규칙이 이미 있어 AWS가 거부한다. prod는 처음부터 새로 만든다.
# preprod 적용 뒤에는 state에 이미 있으므로 이 블록은 아무 일도 하지 않고, 다음 PR에서 지운다.
import {
  for_each = var.environment == "preprod" ? toset(["sgr-0d435fe95c0cc0923"]) : toset([])
  to       = module.service_foundation.aws_vpc_security_group_egress_rule.alb_to_hosts
  id       = each.value
}

import {
  for_each = var.environment == "preprod" ? toset(["sgr-082fd90608e78fde0"]) : toset([])
  to       = module.service_foundation.aws_vpc_security_group_ingress_rule.ecs_host_from_alb
  id       = each.value
}

import {
  for_each = var.environment == "preprod" ? toset(["sgr-0cbdfb459c770a8e4"]) : toset([])
  to       = module.service_foundation.aws_vpc_security_group_egress_rule.ecs_host_all
  id       = each.value
}
