terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket·key·region은 init의 -backend-config로 넘긴다. 새 계정의 첫 apply는
  # backend_override.tf로 local backend를 쓴다(docs/operations.md).
  backend "s3" {
    use_lockfile = true
  }
}

# default_tags를 쓰지 않는다. 모든 리소스의 태그가 바뀌면 IAM 정책 data source가
# 전부 apply 시점으로 미뤄져, 저장 plan에서 정책 JSON을 검토할 수 없다.
provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
}
