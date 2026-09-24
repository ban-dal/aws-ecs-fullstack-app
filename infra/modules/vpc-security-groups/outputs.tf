output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "ecs_host_security_group_id" {
  value = aws_security_group.ecs_host.id
}

output "wireguard_security_group_id" {
  value = try(aws_security_group.wireguard[0].id, null)
}
