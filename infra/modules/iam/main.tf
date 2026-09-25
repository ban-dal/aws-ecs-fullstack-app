# 계정의 IAM 접근 경로를 한곳에서 관리한다. 인프라와 앱 저장소의 OIDC 역할은 분리한다.
# 앱 배포 역할은 각 환경의 ECR 저장소·ECS 서비스만 변경한다.
locals {
  repository_arns = [for environment in var.environments :
  "arn:aws:ecr:${var.region}:${var.account_id}:repository/aws-fullstack-lab-${environment}-web"]
  log_group_arns = [for environment in var.environments :
  "arn:aws:logs:${var.region}:${var.account_id}:log-group:aws-fullstack-lab-${environment}-*"]

  github_subjects = {
    plan        = [for environment in var.environments : "${var.repository_subject}:environment:${environment}-plan"]
    apply       = [for environment in var.environments : "${var.repository_subject}:environment:${environment}-apply"]
    app-preprod = ["${var.app_repository_subject}:ref:refs/heads/preprod"]
    app-prod    = ["${var.app_repository_subject}:environment:prod-deploy"]
  }

  host_role_arn      = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-host"
  execution_role_arn = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-task-execution"
}

# OIDC subject는 각 저장소의 immutable ID와 GitHub 환경 또는 배포 브랜치로 제한한다.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "github_assume" {
  for_each = local.github_subjects

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
      values   = each.value
    }
  }
}

resource "aws_iam_role" "github" {
  for_each             = local.github_subjects
  name                 = "aws-fullstack-lab-${each.key}"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[each.key].json
  max_session_duration = 3600
  tags                 = { Project = "aws-fullstack-lab", Purpose = each.key }
}

# Terraform 역할은 AWS 관리형 정책으로 서비스 권한을 받아, 새 AWS 서비스를 쓸 때 bootstrap
# 정책을 고치지 않는다. plan과 apply를 한 역할로 합치지 않는다. `*-plan` 환경은 승인 없이
# PR 브랜치의 코드(workflow 포함)도 토큰을 받으므로, 여기에 쓰기 권한을 주면 merge와 prod
# 승인을 거치지 않고 적용할 수 있다. 쓰기 역할은 main에서만 배포하는 `*-apply` 환경만
# 수임한다(scripts/check-github-settings.sh).
resource "aws_iam_role_policy_attachment" "github" {
  for_each   = { plan = "ReadOnlyAccess", apply = "PowerUserAccess" }
  role       = aws_iam_role.github[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# ReadOnlyAccess에 state lock 쓰기만 더한다. 환경 plan은 bootstrap state를 읽을 필요가 없다.
data "aws_iam_policy_document" "plan" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for environment in var.environments : "${var.state_bucket_arn}/${environment}/terraform.tfstate.tflock"]
  }
  statement {
    effect    = "Deny"
    actions   = ["s3:GetObject"]
    resources = ["${var.state_bucket_arn}/bootstrap/*"]
  }
}

# PowerUserAccess는 IAM을 허용하지 않으므로 PassRole만 공통 ECS 역할과 정해진 서비스로 연다.
# 서비스 연결 역할 생성은 PowerUserAccess가 허용하므로 서비스가 필요할 때 직접 만든다.
# 비용 상한은 IAM에 두지 않으며 Budget은 알림만 보낸다.
data "aws_iam_policy_document" "apply" {
  statement {
    actions   = ["iam:PassRole"]
    resources = [local.host_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [local.execution_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  # PowerUserAccess는 모든 S3·CloudTrail 변경도 허용한다. GitHub 역할이 state 이력과 감사
  # 로그를 지우거나 bootstrap state를 고치지 못하도록 bootstrap이 소유한 두 기반만 막는다.
  # state 버킷에서는 S3 backend가 쓰는 목록 조회와 객체 읽기·쓰기·삭제만 남긴다. 삭제해도
  # 버전 관리로 이전 버전이 남는다.
  statement {
    effect      = "Deny"
    not_actions = ["s3:ListBucket"]
    resources   = [var.state_bucket_arn]
  }
  statement {
    effect      = "Deny"
    not_actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources   = ["${var.state_bucket_arn}/*"]
  }
  statement {
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${var.state_bucket_arn}/bootstrap/*", var.audit_bucket_arn, "${var.audit_bucket_arn}/*"]
  }
  statement {
    effect    = "Deny"
    actions   = ["cloudtrail:DeleteTrail", "cloudtrail:PutEventSelectors", "cloudtrail:StopLogging", "cloudtrail:UpdateTrail"]
    resources = [var.audit_trail_arn]
  }
}

# 앱 저장소 역할은 환경별 저장소에 이미지를 올리고 해당 ECS 서비스만 갱신한다.
# prod-deploy 환경은 앱 저장소에서 main 전용·승인 필수로 설정한다.
data "aws_iam_policy_document" "app" {
  for_each = toset(["preprod", "prod"])

  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    resources = ["arn:aws:ecr:${var.region}:${var.account_id}:repository/aws-fullstack-lab-${each.key}-web"]
  }
  statement {
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = ["arn:aws:ecs:${var.region}:${var.account_id}:service/aws-fullstack-lab-${each.key}-cluster/web"]
  }
  statement {
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecs:RegisterTaskDefinition", "ecs:TagResource"]
    resources = ["arn:aws:ecs:${var.region}:${var.account_id}:task-definition/aws-fullstack-lab-${each.key}-web:*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = [local.execution_role_arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "github" {
  for_each = local.github_subjects
  name     = { plan = "terraform-plan-read", apply = "terraform-foundation-apply", app-preprod = "preprod-app-deploy", app-prod = "prod-app-deploy" }[each.key]
  role     = aws_iam_role.github[each.key].name
  policy = {
    plan        = data.aws_iam_policy_document.plan.json
    apply       = data.aws_iam_policy_document.apply.json
    app-preprod = data.aws_iam_policy_document.app["preprod"].json
    app-prod    = data.aws_iam_policy_document.app["prod"].json
  }[each.key]
}

# 사람은 IAM 사용자로 로그인하고 MFA 세션으로 운영 역할 하나를 수임한다.
# 콘솔 비밀번호와 MFA 장치는 Terraform 밖에서 등록한다.
resource "aws_iam_user" "operator" {
  name = "aws-fullstack-lab-operator"
  tags = { Project = "aws-fullstack-lab", Purpose = "human-operator" }
}

resource "aws_iam_user_policy_attachment" "sign_in" {
  user       = aws_iam_user.operator.name
  policy_arn = "arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess"
}

data "aws_iam_policy_document" "operator_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:user/aws-fullstack-lab-operator"]
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
  tags                 = { Project = "aws-fullstack-lab", Purpose = "human-operator" }
}

# 실험 계정의 bootstrap을 운영한다. 이 역할은 계정 관리자 권한이므로 MFA를 필수로 둔다.
resource "aws_iam_role_policy_attachment" "operator_admin" {
  role       = aws_iam_role.operator.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "operator_user" {
  statement {
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.operator.arn]
  }
  statement {
    actions   = ["iam:ListVirtualMFADevices"]
    resources = ["*"]
  }
  statement {
    actions   = ["iam:CreateVirtualMFADevice"]
    resources = ["arn:aws:iam::${var.account_id}:mfa/${aws_iam_user.operator.name}"]
  }
  statement {
    actions   = ["iam:ChangePassword", "iam:EnableMFADevice", "iam:GetMFADevice", "iam:GetUser", "iam:ListMFADevices", "iam:ResyncMFADevice"]
    resources = [aws_iam_user.operator.arn]
  }
  statement {
    actions   = ["iam:DeactivateMFADevice"]
    resources = [aws_iam_user.operator.arn]
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
  statement {
    actions   = ["iam:DeleteVirtualMFADevice"]
    resources = ["arn:aws:iam::${var.account_id}:mfa/${aws_iam_user.operator.name}"]
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}

resource "aws_iam_user_policy" "operator" {
  name   = "assume-operator-and-manage-login"
  user   = aws_iam_user.operator.name
  policy = data.aws_iam_policy_document.operator_user.json
}

# ECS 호스트와 태스크 실행 역할은 두 환경이 공유한다. 앱은 AWS API를 호출하지 않아 태스크 역할은 없다.
resource "aws_iam_role" "ecs_host" {
  name = "aws-fullstack-lab-ecs-host"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = { Project = "aws-fullstack-lab", Purpose = "ecs-host" }
}

resource "aws_iam_role_policy_attachment" "ecs_host" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# ECS 호스트 진단은 SSH 대신 SSM으로 한다.
# 호스트 역할은 공통이므로 prod 호스트에도 SSM 에이전트 권한이 부여된다.
resource "aws_iam_role_policy_attachment" "ecs_host_ssm" {
  role       = aws_iam_role.ecs_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_host" {
  name = aws_iam_role.ecs_host.name
  role = aws_iam_role.ecs_host.name
  tags = { Project = "aws-fullstack-lab", Purpose = "ecs-host" }
}

resource "aws_iam_role" "ecs_execution" {
  name = "aws-fullstack-lab-ecs-task-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
  tags = { Project = "aws-fullstack-lab", Purpose = "ecs-task-execution" }
}

data "aws_iam_policy_document" "ecs_execution" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = local.repository_arns
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = local.log_group_arns
  }
}

resource "aws_iam_role_policy" "ecs_execution" {
  name   = "ecs-task-execution"
  role   = aws_iam_role.ecs_execution.name
  policy = data.aws_iam_policy_document.ecs_execution.json
}
