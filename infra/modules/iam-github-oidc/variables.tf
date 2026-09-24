variable "boundary_name" {
  type = string
}

variable "environments" {
  type = set(string)
}

variable "region" {
  type = string
}

variable "state_bucket_arn" {
  type = string
}

variable "passable_role_arns" {
  type        = list(string)
  description = "GitHub 역할이 AWS 서비스에 넘길 수 있는 역할 ARN"
}
