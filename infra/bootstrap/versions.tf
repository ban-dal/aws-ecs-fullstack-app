terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No default_tags here: changing tags on every resource defers all IAM policy
# data sources to apply time, which hides policy JSON from the saved plan.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "expected_account_id" {
  type        = string
  description = "bootstrap을 적용할 AWS 계정 ID. 다른 계정 자격 증명이면 API 호출 전에 실패한다."

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id는 12자리 AWS 계정 ID여야 합니다."
  }
}

variable "state_bucket_name" {
  type        = string
  description = "전역에서 유일한 Terraform state S3 버킷 이름"
}

variable "github_repository_subject" {
  type        = string
  description = "GitHub OIDC sub의 repo 접두사. 소유자·저장소의 immutable ID를 포함해 이름이 바뀌어도 신뢰가 넘어가지 않는다."
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
