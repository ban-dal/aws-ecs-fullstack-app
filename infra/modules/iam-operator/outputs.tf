output "user_arn" {
  value = aws_iam_user.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}
