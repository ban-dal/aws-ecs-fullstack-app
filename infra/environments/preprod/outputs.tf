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

output "ecs_cluster_name" {
  value = module.ecs_cluster.name
}

output "ecs_service_name" {
  value = module.web.service_name
}

output "ecs_autoscaling_group_name" {
  value = module.ecs_host.autoscaling_group_name
}

output "vpn_http_health_url" {
  value = "http://10.62.0.1:3000/api/health"
}

output "client_vpn_endpoint_id" {
  value = module.client_vpn.endpoint_id
}
