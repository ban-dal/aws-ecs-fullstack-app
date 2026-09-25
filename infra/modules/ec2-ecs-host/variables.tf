variable "name_prefix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "public_subnet_id" {
  type    = string
  default = null
}

variable "public_subnet_ids" {
  type    = list(string)
  default = null
}

variable "host_count" {
  type    = number
  default = 1

  validation {
    condition     = var.host_count >= 1 && var.host_count <= 2
    error_message = "host_count는 1 또는 2여야 합니다."
  }
}

variable "imds_hop_limit" {
  type    = number
  default = null
}

variable "security_group_ids" {
  type = list(string)
}

variable "tags" {
  type = map(string)
}
