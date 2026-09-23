# Human access for bootstrap work. The IAM user can only sign in, manage its own
# MFA, and assume the operator role; the role trusts only MFA sessions. An IAM
# Identity Center account instance cannot grant AWS account access, and AWS
# Organizations would end this account's Free plan credits, so a plain IAM user
# is used. The console accepts a passkey, but the CLI and API do not: role
# assumption needs an authenticator app (TOTP) device named after the user.
#
# Changes outside this role's own policy are applied with the account root
# session; docs/operations.md lists which ones.

locals {
  # Role names are fixed so the Deny statements also cover a deleted and
  # recreated role.
  github_role_arns = [
    for name in concat(
      [for environment in local.environments : "aws-fullstack-lab-${environment}-plan"],
      [for environment in local.environments : "aws-fullstack-lab-${environment}-apply"],
    ) : "arn:aws:iam::${local.account_id}:role/${name}"
  ]
}

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
    sid       = "DeleteOwnVirtualMfaDeviceWithMfa"
    actions   = ["iam:DeleteVirtualMFADevice"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/${aws_iam_user.operator.name}"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DeactivateOwnMfaWithMfa"
    actions   = ["iam:DeactivateMFADevice"]
    resources = [aws_iam_user.operator.arn]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
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
    sid       = "ManageProjectBootstrapIdentity"
    actions   = ["iam:*"]
    resources = concat([aws_iam_openid_connect_provider.github.arn], local.github_role_arns)
  }

  statement {
    sid = "ReadGitHubBoundary"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyTags",
      "iam:ListPolicyVersions",
    ]
    resources = [local.github_boundary_arn]
  }

  statement {
    sid       = "KeepGitHubRoleBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = local.github_role_arns
  }

  statement {
    sid       = "RequireGitHubRoleBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = local.github_role_arns

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [local.github_boundary_arn]
    }
  }

  statement {
    sid = "ReadOwnOperatorIdentity"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
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
    actions   = ["budgets:ListTagsForResource", "budgets:ViewBudget"]
    resources = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/aws-fullstack-lab-monthly"]
  }

  # Lets scripts/bootstrap.sh run the policy tests before an apply. The
  # simulator only evaluates policies passed in the request.
  statement {
    sid       = "SimulateBootstrapPolicies"
    actions   = ["iam:SimulateCustomPolicy"]
    resources = ["*"]
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
