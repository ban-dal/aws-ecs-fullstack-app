# 사람이 bootstrap을 운영하기 위한 접근 경로다. IAM 사용자는 로그인, 자기 MFA
# 관리, 운영 역할 수임만 할 수 있고, 운영 역할은 MFA 세션만 신뢰한다. IAM
# Identity Center의 account instance는 AWS 계정 접근 권한을 줄 수 없고, AWS
# Organizations에 가입하면 이 계정의 Free plan 크레딧이 끝나므로 일반 IAM
# 사용자를 쓴다. 콘솔은 패스키를 받지만 CLI/API는 받지 않으므로, 역할 수임에는
# 사용자 이름과 같은 이름의 인증 앱(TOTP) 장치가 필요하다.
#
# 이 역할 정책의 권한 밖인 변경은 계정 root 세션으로 적용한다. 어떤 변경인지는
# docs/operations.md에 있다.

locals {
  # 역할 이름을 고정해 두어야 역할을 삭제한 뒤 다시 만들어도 Deny가 적용된다.
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

# 콘솔 비밀번호와 MFA 장치는 Terraform 밖에서 등록한다. 비밀번호와 복구 자료가
# state나 PR에 들어가지 않게 하기 위해서다.
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

  # scripts/bootstrap.sh가 apply 전에 정책 테스트를 실행하기 위한 권한이다.
  # 시뮬레이터는 요청에 넣은 정책을 판정할 뿐 권한을 주지 않는다.
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
