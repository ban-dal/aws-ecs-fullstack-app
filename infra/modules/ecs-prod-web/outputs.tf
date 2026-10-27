output "service_name" {
  value = aws_ecs_service.web.name
}

output "ecs_infrastructure_role_arn" {
  value = aws_iam_role.ecs_infrastructure.arn
}
