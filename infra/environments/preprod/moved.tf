# 모듈로 나누기 전의 리소스 주소를 새 주소로 옮긴다. state 안에서만 이동하며 AWS
# 리소스는 바뀌지 않는다. prod는 state가 비어 있어 옮길 것이 없으므로 preprod에만 둔다.
# 적용한 뒤 다음 PR에서 이 파일을 지운다.

moved {
  from = module.service_foundation.aws_vpc.app
  to   = module.vpc.aws_vpc.this
}

moved {
  from = module.service_foundation.aws_internet_gateway.app
  to   = module.vpc.aws_internet_gateway.this
}

moved {
  from = module.service_foundation.aws_subnet.public
  to   = module.vpc.aws_subnet.public
}

moved {
  from = module.service_foundation.aws_subnet.private
  to   = module.vpc.aws_subnet.private
}

moved {
  from = module.service_foundation.aws_route_table.public
  to   = module.vpc.aws_route_table.public
}

moved {
  from = module.service_foundation.aws_route_table.private
  to   = module.vpc.aws_route_table.private
}

moved {
  from = module.service_foundation.aws_route.public_internet
  to   = module.vpc.aws_route.public_internet
}

moved {
  from = module.service_foundation.aws_route_table_association.public
  to   = module.vpc.aws_route_table_association.public
}

moved {
  from = module.service_foundation.aws_route_table_association.private
  to   = module.vpc.aws_route_table_association.private
}

moved {
  from = module.service_foundation.aws_security_group.alb
  to   = module.vpc_security_groups.aws_security_group.alb
}

moved {
  from = module.service_foundation.aws_security_group.ecs_host
  to   = module.vpc_security_groups.aws_security_group.ecs_host
}

moved {
  from = module.service_foundation.aws_vpc_security_group_egress_rule.alb_to_hosts
  to   = module.vpc_security_groups.aws_vpc_security_group_egress_rule.alb_to_hosts
}

moved {
  from = module.service_foundation.aws_vpc_security_group_ingress_rule.ecs_host_from_alb
  to   = module.vpc_security_groups.aws_vpc_security_group_ingress_rule.ecs_host_from_alb
}

moved {
  from = module.service_foundation.aws_vpc_security_group_egress_rule.ecs_host_all
  to   = module.vpc_security_groups.aws_vpc_security_group_egress_rule.ecs_host_all
}

moved {
  from = module.service_foundation.aws_ecr_repository.web
  to   = module.ecr_repository.aws_ecr_repository.this
}

moved {
  from = module.service_foundation.aws_ecr_lifecycle_policy.web
  to   = module.ecr_repository.aws_ecr_lifecycle_policy.this
}
