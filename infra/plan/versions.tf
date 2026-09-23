terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["preprod", "prod"], var.environment)
    error_message = "environment는 preprod 또는 prod여야 합니다."
  }
}

variable "expected_account_id" {
  type        = string
  description = "bootstrap을 적용한 AWS 계정 ID"
}

variable "availability_zones" {
  type        = list(string)
  description = "서로 다른 두 가용 영역. 계정에서 사용 가능한 AZ를 확인하고 지정한다."
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  validation {
    condition     = length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2
    error_message = "availability_zones에는 서로 다른 가용 영역 두 개가 필요합니다."
  }
}

data "aws_caller_identity" "current" {}

output "plan_identity" {
  value = {
    environment = var.environment
    account_id  = data.aws_caller_identity.current.account_id
  }

  precondition {
    condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
    error_message = "OIDC 역할의 AWS 계정이 bootstrap 계정과 다릅니다."
  }
}
