variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "github_subject_suffix" {
  type        = string
  description = "앱 저장소 subject 뒤에 붙는 배포 조건. 예: ref:refs/heads/preprod, environment:prod-deploy"
}

variable "read_alb_target_health" {
  type    = bool
  default = false
}

variable "ecs_infrastructure_role_arn" {
  type     = string
  default  = null
  nullable = true
}
