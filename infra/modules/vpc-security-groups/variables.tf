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

variable "enable_wireguard" {
  type    = bool
  default = false
}
