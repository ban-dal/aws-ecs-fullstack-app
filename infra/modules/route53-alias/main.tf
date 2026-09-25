# 위임된 서비스 영역의 apex를 prod ALB로 연결한다. ALB zone ID와 서비스
# 호스팅 영역 ID는 서로 다르므로 각각 알맞은 곳에 쓴다.
data "aws_route53_zone" "service" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "web" {
  zone_id = data.aws_route53_zone.service.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}
