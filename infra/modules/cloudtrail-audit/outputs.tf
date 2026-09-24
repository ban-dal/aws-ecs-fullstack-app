# 이름으로 ARN을 만들어 trail과 버킷을 만들기 전에도 참조할 수 있게 한다.
output "trail_arn" {
  value = local.trail_arn
}

output "bucket_arn" {
  value = "arn:aws:s3:::${var.bucket_name}"
}
