# AWS 서비스가 계정 안에서 쓰는 서비스 연결 역할이다. 이 역할이 없으면 ECS와 EC2 Auto
# Scaling은 처음 리소스를 만들 때 호출자의 iam:CreateServiceLinkedRole 권한으로 역할을
# 만든다. GitHub apply 역할에 IAM 생성 권한을 주지 않도록 bootstrap에서 미리 만든다.
# 역할의 권한은 AWS가 정하며 바꿀 수 없다.

resource "aws_iam_service_linked_role" "this" {
  for_each = var.service_names

  aws_service_name = each.value
}
