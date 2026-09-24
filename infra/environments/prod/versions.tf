terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket·key·region은 init의 -backend-config로 넘긴다. key는
  # <environment>/terraform.tfstate다.
  backend "s3" {
    use_lockfile = true
  }
}

# 다른 계정의 자격 증명이면 AWS API를 호출하기 전에 실패한다.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}
