# ECR 이미지 스캔은 저장소가 아니라 레지스트리(계정·리전) 단위로 설정한다. 저장소 단위
# imageScanningConfiguration은 AWS가 지원 중단 예정으로 안내한다. 계정 단위 설정이라
# 서비스 기반이 아닌 bootstrap에서 호출하고 운영 역할로 적용한다. BASIC 스캔은 무료다.
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "BASIC"

  rule {
    scan_frequency = "SCAN_ON_PUSH"

    repository_filter {
      filter      = var.repository_filter
      filter_type = "WILDCARD"
    }
  }
}
