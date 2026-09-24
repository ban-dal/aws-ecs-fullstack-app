variable "account_id" {
  type = string
}

variable "environments" {
  type = set(string)
}

variable "region" {
  type = string
}

variable "repository_arns" {
  type        = map(string)
  description = "환경별 ECR 저장소 ARN"
}

variable "log_group_arns" {
  type        = map(string)
  description = "환경별 CloudWatch 로그 그룹 ARN 패턴"
}
