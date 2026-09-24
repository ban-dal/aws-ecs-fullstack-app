variable "name" {
  type        = string
  description = "호스팅 영역 이름. 부모 도메인에서 위임받는 하위 도메인이다."
}

variable "caa_issuers" {
  type        = list(string)
  description = "이 영역 아래 이름에 인증서를 발급할 수 있는 인증 기관"
}
