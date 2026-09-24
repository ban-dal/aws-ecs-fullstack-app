variable "account_id" {
  type = string
}

variable "state_bucket_arn" {
  type = string
}

variable "github_oidc_provider_arn" {
  type = string
}

variable "github_role_arns" {
  type        = list(string)
  description = "운영 역할이 관리하는 GitHub plan·apply·image 역할 ARN"
}

variable "github_boundary_arn" {
  type        = string
  description = "GitHub 역할 boundary ARN. 운영 역할은 읽기만 하고 제거·교체하지 못한다."
}

variable "service_identity_arns" {
  type        = list(string)
  description = "운영 역할이 읽기만 하는 ECS 역할과 인스턴스 프로파일 ARN"
}

variable "budget_name" {
  type = string
}
