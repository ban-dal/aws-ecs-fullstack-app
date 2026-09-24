# root 로그인(성공·실패)을 이메일로 알린다. root는 비상용이므로 쓰일 때마다 알아야 한다.
# AWS User Notifications는 무료이고, 한 규칙으로 여러 리전의 EventBridge 이벤트를 받는다.
# 이벤트는 cloudtrail-audit의 trail이 있어야 전달된다.
#
# 인프라 관리자 역할의 수임은 알리지 않는다. 매일 쓰는 역할이라 알림이 소음이 되고,
# AssumeRole은 읽기 전용 이벤트라 기본 규칙에 잡히지 않는다.
#
# 이메일 연락처는 만든 뒤 AWS가 보내는 확인 메일에서 승인해야 알림이 간다.

resource "aws_notifications_notification_hub" "this" {
  notification_hub_region = var.hub_region
}

resource "aws_notificationscontacts_email_contact" "this" {
  name          = "aws-fullstack-lab-alerts"
  email_address = var.email

  tags = {
    Project = "aws-fullstack-lab"
  }
}

resource "aws_notifications_notification_configuration" "this" {
  name                 = "aws-fullstack-lab-root-sign-in"
  description          = "Root user console sign-in"
  aggregation_duration = "NONE"

  tags = {
    Project = "aws-fullstack-lab"
  }

  depends_on = [aws_notifications_notification_hub.this]
}

# root 로그인은 us-east-1, us-east-2, us-west-2 중 한 곳에 기록된다. aws login처럼 리전
# 엔드포인트를 쓰는 로그인에 대비해 이 프로젝트 리전도 받는다.
resource "aws_notifications_event_rule" "this" {
  notification_configuration_arn = aws_notifications_notification_configuration.this.arn
  source                         = "aws.signin"
  event_type                     = "AWS Console Sign In via CloudTrail"
  regions                        = var.regions
  event_pattern = jsonencode({
    detail = {
      userIdentity = { type = ["Root"] }
    }
  })
}

resource "aws_notifications_channel_association" "this" {
  arn                            = aws_notificationscontacts_email_contact.this.arn
  notification_configuration_arn = aws_notifications_notification_configuration.this.arn
}
