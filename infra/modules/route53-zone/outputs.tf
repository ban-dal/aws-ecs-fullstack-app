output "zone_id" {
  value = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "부모 도메인(Vercel DNS)에 NS 레코드로 추가할 네임서버"
  value       = aws_route53_zone.this.name_servers
}
