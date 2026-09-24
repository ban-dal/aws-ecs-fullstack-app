# 월간 비용 알림이다. 크레딧을 제외한 사용 비용이 한도의 80%를 넘으면(실제),
# 100%를 넘을 것으로 예상되면(예측) 이메일을 보낸다. 알림만 하고 지출을 멈추지 않는다.
# 알림 주소가 없으면 만들지 않는다.

resource "aws_budgets_budget" "monthly" {
  count        = var.alert_email == null ? 0 : 1
  name         = var.name
  budget_type  = "COST"
  limit_amount = tostring(var.limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
