variable "name_prefix" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "tags" {
  type = map(string)
}
