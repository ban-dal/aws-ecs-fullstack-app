output "role_arns" {
  value = { for service, role in aws_iam_service_linked_role.this : service => role.arn }
}
