output "dns_name" {
  value = aws_lb.web.dns_name
}

output "zone_id" {
  value = aws_lb.web.zone_id
}

output "target_group_arn" {
  value = aws_lb_target_group.web.arn
}

output "https_listener_arn" {
  value = aws_lb_listener.https.arn
}
