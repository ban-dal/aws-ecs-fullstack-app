locals {
  environments = toset(["preprod", "prod"])
  account_id   = data.aws_caller_identity.current.account_id

  web_repository_arns = {
    for environment in local.environments :
    environment => "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/aws-fullstack-lab-${environment}-web"
  }

  foundation_read_actions = [
    "ec2:DescribeAvailabilityZones",
    "ec2:DescribeInternetGateways",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeRouteTables",
    "ec2:DescribeSecurityGroupRules",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeTags",
    "ec2:DescribeVpcAttribute",
    "ec2:DescribeVpcs",
  ]
}

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

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
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
  for_each = local.environments

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
      values   = ["${var.github_repository_subject}:environment:${each.key}-plan"]
    }
  }
}

resource "aws_iam_role" "plan" {
  for_each = local.environments

  name                 = "aws-fullstack-lab-${each.key}-plan"
  assume_role_policy   = data.aws_iam_policy_document.plan_assume[each.key].json
  permissions_boundary = local.github_boundary_arn
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "terraform-plan"
  }

  depends_on = [aws_iam_policy.github_boundary]
}

data "aws_iam_policy_document" "plan" {
  for_each = local.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadOwnState"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate"]
  }

  statement {
    sid       = "LockOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ReadFoundationNetwork"
    actions   = local.foundation_read_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ReadOwnRepository"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
    ]
    resources = [local.web_repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "plan" {
  for_each = local.environments

  name   = "terraform-plan-read"
  role   = aws_iam_role.plan[each.key].name
  policy = data.aws_iam_policy_document.plan[each.key].json
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

output "plan_role_arns" {
  value = { for environment, role in aws_iam_role.plan : environment => role.arn }
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
