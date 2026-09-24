variable "account_id" {
  type = string
}

variable "environments" {
  type = set(string)
}

variable "region" {
  type = string
}

variable "repository_subject" {
  type        = string
  description = "GitHub OIDC sub의 repo 접두사"
}

variable "oidc_provider_arn" {
  type = string
}

variable "boundary_arn" {
  type = string
}

variable "repository_arns" {
  type        = map(string)
  description = "환경별 ECR 저장소 ARN"
}
