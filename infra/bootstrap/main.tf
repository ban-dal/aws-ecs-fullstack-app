resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false
  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "terraform-state"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "state_tls" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state_tls" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.state_tls.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "plan_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        for environment in ["preprod-plan", "prod-plan"] :
        "${var.github_repository_subject}:environment:${environment}"
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name               = "aws-fullstack-lab-plan"
  assume_role_policy = data.aws_iam_policy_document.plan_assume.json
}

data "aws_iam_policy_document" "state_plan" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "ReadEnvironmentState"
    actions = ["s3:GetObject"]
    resources = [
      for environment in ["preprod", "prod"] :
      "${aws_s3_bucket.state.arn}/${environment}/terraform.tfstate"
    ]
  }

  statement {
    sid     = "LockEnvironmentState"
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      for environment in ["preprod", "prod"] :
      "${aws_s3_bucket.state.arn}/${environment}/terraform.tfstate.tflock"
    ]
  }
}

resource "aws_iam_role_policy" "state_plan" {
  name   = "terraform-state-lock"
  role   = aws_iam_role.plan.name
  policy = data.aws_iam_policy_document.state_plan.json
}

data "aws_iam_policy_document" "foundation_plan_read" {
  statement {
    sid       = "ReadVpcFoundation"
    actions   = ["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeSubnets", "ec2:DescribeInternetGateways", "ec2:DescribeRouteTables", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags"]
    resources = ["*"]
  }

  statement {
    sid = "ReadEnvironmentRepositories"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
    ]
    resources = [
      for environment in ["preprod", "prod"] :
      "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/aws-fullstack-lab-${environment}-web"
    ]
  }
}

resource "aws_iam_role_policy" "foundation_plan_read" {
  name   = "terraform-foundation-read"
  role   = aws_iam_role.plan.name
  policy = data.aws_iam_policy_document.foundation_plan_read.json
}

resource "aws_budgets_budget" "monthly" {
  count        = var.budget_alert_email == null ? 0 : 1
  name         = "aws-fullstack-lab-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
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
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
