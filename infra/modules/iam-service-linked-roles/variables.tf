variable "service_names" {
  type        = set(string)
  description = "서비스 연결 역할을 만들 AWS 서비스 주체 이름(예: ecs.amazonaws.com)"
}
