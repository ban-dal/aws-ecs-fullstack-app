variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "enable_client_vpn" {
  type    = bool
  default = false
}

variable "enable_public_https" {
  type    = bool
  default = false
}
