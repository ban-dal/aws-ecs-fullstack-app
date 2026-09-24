variable "name" {
  type        = string
  description = "저장소 이름. bootstrap의 적용 역할 권한이 이 이름을 가리킨다."
}

variable "tags" {
  type = map(string)
}
