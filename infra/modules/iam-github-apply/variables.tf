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

variable "state_bucket_arn" {
  type = string
}

variable "repository_arns" {
  type        = map(string)
  description = "환경별 ECR 저장소 ARN"
}

variable "host_role_arns" {
  type        = map(string)
  description = "환경별 ECS 호스트 역할 ARN. EC2에만 넘길 수 있다."
}

variable "execution_role_arns" {
  type        = map(string)
  description = "환경별 ECS 태스크 실행 역할 ARN. ECS 태스크에만 넘길 수 있다."
}
