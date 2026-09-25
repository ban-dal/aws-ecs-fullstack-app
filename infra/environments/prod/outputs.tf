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

output "site_url" {
  value = "https://${module.dns.fqdn}"
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.name
}

output "ecs_autoscaling_group_name" {
  value = module.ecs_host.autoscaling_group_name
}
