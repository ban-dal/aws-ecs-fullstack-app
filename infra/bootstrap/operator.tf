resource "aws_iam_user" "operator" {
  name = "aws-fullstack-lab-operator"

  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "human-bootstrap-operator"
  }
}

# The console password and MFA device are enrolled outside Terraform so neither
# the password nor its recovery material enters state or a pull request.
resource "aws_iam_user_policy_attachment" "operator_login" {
  user       = aws_iam_user.operator.name
  policy_arn = "arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess"
}

data "aws_iam_policy_document" "operator_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.operator.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "operator" {
  name                 = "aws-fullstack-lab-bootstrap-operator"
  assume_role_policy   = data.aws_iam_policy_document.operator_assume.json
  max_session_duration = 3600

  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "human-bootstrap-operator"
  }
}

data "aws_iam_policy_document" "operator_user" {
  statement {
    sid       = "AssumeBootstrapOperatorOnly"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.operator.arn]
  }

  statement {
    sid       = "ListMfaDevicesForEnrollment"
    actions   = ["iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateOwnVirtualMfaDevice"
    actions   = ["iam:CreateVirtualMFADevice"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/${aws_iam_user.operator.name}"]
  }

  statement {
    sid = "ManageOwnLoginAndMfa"
    actions = [
      "iam:ChangePassword",
      "iam:EnableMFADevice",
      "iam:GetMFADevice",
      "iam:GetUser",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
    ]
    resources = [aws_iam_user.operator.arn]
  }
}

resource "aws_iam_user_policy" "operator" {
  name   = "assume-bootstrap-operator"
  user   = aws_iam_user.operator.name
  policy = data.aws_iam_policy_document.operator_user.json
}

data "aws_iam_policy_document" "operator_permissions" {
  statement {
    sid       = "ManageProjectStateBucket"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid     = "ManageProjectBootstrapIdentity"
    actions = ["iam:*"]
    resources = concat(
      [aws_iam_openid_connect_provider.github.arn, aws_iam_role.plan.arn],
      [for role in aws_iam_role.foundation_apply : role.arn],
    )
  }

  statement {
    sid = "ReadOwnOperatorIdentity"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
    ]
    resources = [aws_iam_role.operator.arn]
  }

  statement {
    sid = "ReadOwnUserConfiguration"
    actions = [
      "iam:GetUser",
      "iam:GetUserPolicy",
      "iam:ListAttachedUserPolicies",
      "iam:ListUserPolicies",
    ]
    resources = [aws_iam_user.operator.arn]
  }

  statement {
    sid       = "ReadProjectBudget"
    actions   = ["budgets:ViewBudget"]
    resources = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/aws-fullstack-lab-monthly"]
  }

  statement {
    sid       = "ViewBillingForBudget"
    actions   = ["aws-portal:ViewBilling"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "operator" {
  name   = "terraform-bootstrap-operator"
  role   = aws_iam_role.operator.name
  policy = data.aws_iam_policy_document.operator_permissions.json
}

output "operator_user_arn" {
  value = aws_iam_user.operator.arn
}

output "operator_role_arn" {
  value = aws_iam_role.operator.arn
}
