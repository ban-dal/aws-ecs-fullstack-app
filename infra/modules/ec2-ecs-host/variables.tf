variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "security_group_ids" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
