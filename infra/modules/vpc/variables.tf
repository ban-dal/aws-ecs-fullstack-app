variable "name_prefix" {
  type = string
}

variable "cidr_block" {
  type = string
}

variable "availability_zones" {
  type        = list(string)
  description = "서로 다른 두 가용 영역"
}

variable "tags" {
  type = map(string)
}
