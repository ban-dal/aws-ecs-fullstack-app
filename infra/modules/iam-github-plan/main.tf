# 환경별 PR plan 역할이다. 자기 환경의 *-plan GitHub 환경만 신뢰하고, 자기 state를
# 읽고 잠그며 서비스 기반을 refresh할 권한만 가진다. state 쓰기 권한은 없다.

locals {
  role_names = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-plan" }
}

data "aws_iam_policy_document" "assume" {
  for_each = var.environments

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.repository_subject}:environment:${each.key}-plan"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.environments

  name                 = local.role_names[each.key]
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  permissions_boundary = var.boundary_arn
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "terraform-plan"
  }
}

data "aws_iam_policy_document" "permissions" {
  for_each = var.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid       = "ReadOwnState"
    actions   = ["s3:GetObject"]
    resources = ["${var.state_bucket_arn}/${each.key}/terraform.tfstate"]
  }

  statement {
    sid       = "LockOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/${each.key}/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ReadFoundationNetwork"
    actions   = var.read_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid = "ReadOwnRepository"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
    ]
    resources = [var.repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.environments

  name   = "terraform-plan-read"
  role   = aws_iam_role.this[each.key].name
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
