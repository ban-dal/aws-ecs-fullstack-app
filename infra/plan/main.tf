module "service_foundation" {
  source = "../live"

  environment        = var.environment
  availability_zones = var.availability_zones
}

output "service_foundation" {
  value = {
    vpc_id              = module.service_foundation.vpc_id
    public_subnet_ids   = module.service_foundation.public_subnet_ids
    private_subnet_ids  = module.service_foundation.private_subnet_ids
    alb_security_group  = module.service_foundation.alb_security_group_id
    host_security_group = module.service_foundation.host_security_group_id
    ecr_repository_url  = module.service_foundation.ecr_repository_url
  }
}
