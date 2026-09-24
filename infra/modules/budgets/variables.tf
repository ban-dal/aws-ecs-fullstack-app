variable "name" {
  type = string
}

variable "alert_email" {
  type     = string
  nullable = true
}

variable "limit_usd" {
  type = number
}
