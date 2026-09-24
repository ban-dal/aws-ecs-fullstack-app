variable "email" {
  type      = string
  sensitive = true
}

variable "hub_region" {
  type        = string
  description = "알림 데이터를 저장하는 User Notifications hub 리전"
}

variable "regions" {
  type        = list(string)
  description = "root 로그인 이벤트를 받을 리전"
}
