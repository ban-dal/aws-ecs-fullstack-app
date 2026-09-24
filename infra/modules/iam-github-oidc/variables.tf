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
