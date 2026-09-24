variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "server_certificate_arn" {
  type      = string
  sensitive = true
}

variable "tags" {
  type = map(string)
}
