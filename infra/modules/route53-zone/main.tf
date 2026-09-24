# 서비스 주소에 쓰는 Route 53 호스팅 영역이다. 부모 도메인 bandal.dev는 Vercel이
# 등록·관리하므로, 이 영역의 네임서버를 Vercel DNS에 NS 레코드로 추가해야 위임된다
# (docs/operations.md). 두 환경이 하위 이름으로 함께 쓰는 계정 단위 리소스라 bootstrap에서
# 호출하고 root로 적용한다.
#
# 인증 기관은 CAA 레코드를 찾을 때 이름을 위로 거슬러 올라간다. 부모 bandal.dev의 CAA에는
# Amazon이 없어서, 이 영역에 CAA를 두지 않으면 ACM 인증서 발급이 거부된다. 이 영역에
# CAA를 두면 확인이 여기서 멈추므로 Vercel 쪽 CAA는 바꾸지 않는다.

resource "aws_route53_zone" "this" {
  name    = var.name
  comment = "aws-fullstack-lab service domain delegated from Vercel DNS"

  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "service-dns"
  }
}

resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.name
  type    = "CAA"
  ttl     = 300
  records = [for issuer in var.caa_issuers : "0 issue \"${issuer}\""]
}
