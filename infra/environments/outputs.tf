output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "alb_security_group_id" {
  value = module.vpc_security_groups.alb_security_group_id
}

output "ecs_host_security_group_id" {
  value = module.vpc_security_groups.ecs_host_security_group_id
}

output "ecr_repository_url" {
  value = module.ecr_repository.repository_url
}
