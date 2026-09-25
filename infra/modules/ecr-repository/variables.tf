variable "name" {
  type        = string
  description = "저장소 이름. bootstrap의 적용 역할 권한이 이 이름을 가리킨다."
}

variable "push_role_arn" {
  type        = string
  description = "이미지를 push할 수 있는 유일한 역할. bootstrap의 image 역할이다."
}

variable "tags" {
  type = map(string)
}
