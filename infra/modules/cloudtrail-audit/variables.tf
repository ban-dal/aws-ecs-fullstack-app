variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "trail_name" {
  type = string
}

variable "bucket_name" {
  type        = string
  description = "전역에서 유일한 감사 로그 S3 버킷 이름"
}
