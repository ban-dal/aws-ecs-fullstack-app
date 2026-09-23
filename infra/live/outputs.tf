output "vpc_id" {
  value = aws_vpc.app.id
}

output "public_subnet_ids" {
  value = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  value = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "host_security_group_id" {
  value = aws_security_group.ecs_host.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.web.repository_url
}
