variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "expected_account_id" {
  type        = string
  description = "bootstrap을 적용한 AWS 계정 ID"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "expected_account_id는 12자리 AWS 계정 ID여야 합니다."
  }
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
