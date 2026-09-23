terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "state_bucket_name" {
  type        = string
  description = "전역에서 유일한 Terraform state S3 버킷 이름"
}

variable "github_repository_subject" {
  type        = string
  description = "GitHub OIDC sub의 repo 접두사. 저장소의 immutable subject 값을 확인한다."
  default     = "repo:ban-dal@46153202/aws-ecs-fullstack-app@1382568125"

  validation {
    condition     = startswith(var.github_repository_subject, "repo:")
    error_message = "github_repository_subject는 repo:로 시작해야 합니다."
  }
}

variable "budget_alert_email" {
  type        = string
  default     = null
  description = "월간 비용 알림 주소. null이면 Budget을 생성하지 않는다."
  nullable    = true
}

variable "monthly_budget_usd" {
  type    = number
  default = 5

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd는 0보다 커야 합니다."
  }
}
