# 사람이 bootstrap을 운영하기 위한 접근 경로다. IAM 사용자는 로그인, 자기 MFA
# 관리, 운영 역할 수임만 할 수 있고, 운영 역할은 MFA 세션만 신뢰한다. IAM
# Identity Center의 account instance는 AWS 계정 접근 권한을 줄 수 없고, AWS
# Organizations에 가입하면 이 계정의 Free plan 크레딧이 끝나므로 일반 IAM
# 사용자를 쓴다. 콘솔은 패스키를 받지만 CLI/API는 받지 않으므로, 역할 수임에는
# 사용자 이름과 같은 이름의 인증 앱(TOTP) 장치가 필요하다.
#
# 이 역할 정책의 권한 밖인 변경은 계정 root 세션으로 적용한다. 어떤 변경인지는
# docs/operations.md에 있다.

resource "aws_iam_user" "this" {
  name = "aws-fullstack-lab-operator"

  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "human-bootstrap-operator"
  }
}

# 콘솔 비밀번호와 MFA 장치는 Terraform 밖에서 등록한다. 비밀번호와 복구 자료가
# state나 PR에 들어가지 않게 하기 위해서다.
resource "aws_iam_user_policy_attachment" "sign_in" {
  user       = aws_iam_user.this.name
  policy_arn = "arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_user.this.arn]
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "aws-fullstack-lab-bootstrap-operator"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600

  tags = {
    Project = "aws-fullstack-lab"
    Purpose = "human-bootstrap-operator"
  }
}

data "aws_iam_policy_document" "user" {
  statement {
    sid       = "AssumeBootstrapOperatorOnly"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.this.arn]
  }

  statement {
    sid       = "ListMfaDevicesForEnrollment"
    actions   = ["iam:ListVirtualMFADevices"]
    resources = ["*"]
  }

  statement {
    sid       = "CreateOwnVirtualMfaDevice"
    actions   = ["iam:CreateVirtualMFADevice"]
    resources = ["arn:aws:iam::${var.account_id}:mfa/${aws_iam_user.this.name}"]
  }

  statement {
    sid       = "DeleteOwnVirtualMfaDeviceWithMfa"
    actions   = ["iam:DeleteVirtualMFADevice"]
    resources = ["arn:aws:iam::${var.account_id}:mfa/${aws_iam_user.this.name}"]

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DeactivateOwnMfaWithMfa"
    actions   = ["iam:DeactivateMFADevice"]
    resources = [aws_iam_user.this.arn]

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
    resources = [aws_iam_user.this.arn]
  }
}

resource "aws_iam_user_policy" "this" {
  name   = "assume-bootstrap-operator"
  user   = aws_iam_user.this.name
  policy = data.aws_iam_policy_document.user.json
}

data "aws_iam_policy_document" "role" {
  statement {
    sid       = "ManageProjectStateBucket"
    actions   = ["s3:*"]
    resources = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
  }

  statement {
    sid       = "ManageProjectBootstrapIdentity"
    actions   = ["iam:*"]
    resources = concat([var.github_oidc_provider_arn], var.github_role_arns)
  }

  statement {
    sid = "ReadGitHubBoundary"
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyTags",
      "iam:ListPolicyVersions",
    ]
    resources = [var.github_boundary_arn]
  }

  statement {
    sid       = "KeepGitHubRoleBoundary"
    effect    = "Deny"
    actions   = ["iam:DeleteRolePermissionsBoundary"]
    resources = var.github_role_arns
  }

  statement {
    sid       = "RequireGitHubRoleBoundary"
    effect    = "Deny"
    actions   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
    resources = var.github_role_arns

    condition {
      test     = "StringNotEquals"
      variable = "iam:PermissionsBoundary"
      values   = [var.github_boundary_arn]
    }
  }

  # bootstrap plan이 ECS 역할과 서비스 연결 역할을 refresh하기 위한 읽기 권한이다. GitHub
  # apply 역할이 이 역할들을 서비스에 넘기므로 운영 역할은 고치지 못하고, 변경은 root로 적용한다.
  statement {
    sid = "ReadServiceIdentities"
    actions = [
      "iam:GetInstanceProfile",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfileTags",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
    ]
    resources = concat(
      var.service_identity_arns,
      ["arn:aws:iam::${var.account_id}:role/aws-service-role/*"],
    )
  }

  statement {
    sid = "ReadOwnOperatorIdentity"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
    ]
    resources = [aws_iam_role.this.arn]
  }

  statement {
    sid = "ReadOwnUserConfiguration"
    actions = [
      "iam:GetUser",
      "iam:GetUserPolicy",
      "iam:ListAttachedUserPolicies",
      "iam:ListUserPolicies",
    ]
    resources = [aws_iam_user.this.arn]
  }

  statement {
    sid       = "ReadProjectBudget"
    actions   = ["budgets:ListTagsForResource", "budgets:ViewBudget"]
    resources = ["arn:aws:budgets::${var.account_id}:budget/${var.budget_name}"]
  }

  # bootstrap plan이 레지스트리 스캔 설정을 refresh하기 위한 읽기 권한이다. 이 API는
  # 리소스 수준 권한을 지원하지 않는다.
  statement {
    sid       = "ReadRegistryScanning"
    actions   = ["ecr:GetRegistryScanningConfiguration"]
    resources = ["*"]
  }

  # bootstrap plan이 서비스 DNS 영역과 레코드를 refresh하기 위한 읽기 권한이다. 영역과
  # 레코드 변경은 root로 적용한다.
  statement {
    sid = "ReadServiceDnsZone"
    actions = [
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["arn:aws:route53:::hostedzone/*"]
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

resource "aws_iam_role_policy" "this" {
  name   = "terraform-bootstrap-operator"
  role   = aws_iam_role.this.name
  policy = data.aws_iam_policy_document.role.json
}
