output "ecs_host_role_arn" { value = local.host_role_arn }
output "ecs_task_execution_role_arn" { value = local.execution_role_arn }
output "operator_role_arn" { value = aws_iam_role.operator.arn }
output "operator_user_arn" { value = aws_iam_user.operator.arn }
