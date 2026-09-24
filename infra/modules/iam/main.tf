# 계정의 IAM 접근 경로를 한곳에서 관리한다. 사람 1명, GitHub 작업 3종, ECS 서비스 2종이다.
# GitHub와 ECS 역할은 preprod·prod가 공유한다. 환경 간 IAM 격리는 제공하지 않는다.
locals {
  repository_arns = [for environment in var.environments :
  "arn:aws:ecr:${var.region}:${var.account_id}:repository/aws-fullstack-lab-${environment}-web"]
  log_group_arns = [for environment in var.environments :
  "arn:aws:logs:${var.region}:${var.account_id}:log-group:aws-fullstack-lab-${environment}-*"]

  github_subjects = {
    plan  = [for environment in var.environments : "${var.repository_subject}:environment:${environment}-plan"]
    apply = [for environment in var.environments : "${var.repository_subject}:environment:${environment}-apply"]
    image = ["${var.repository_subject}:ref:refs/heads/main"]
  }

  host_role_arn      = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-host"
  execution_role_arn = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-task-execution"
}

# OIDC subject는 immutable repository ID와 GitHub 환경 또는 main 브랜치로 제한한다.
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

# 계정의 첫 AWS Client VPN 엔드포인트는 서비스 연결 역할을 자동 생성하려 한다.
# GitHub apply 역할에 IAM 생성 권한을 주지 않도록 bootstrap에서 한 번 만든다.
resource "aws_iam_service_linked_role" "client_vpn" {
  aws_service_name = "clientvpn.amazonaws.com"
}

# plan은 두 환경 state 본문을 읽고 각 lock 객체만 변경한다. 서비스 refresh는 조회만 한다.
data "aws_iam_policy_document" "plan" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = [for environment in var.environments : "${var.state_bucket_arn}/${environment}/terraform.tfstate"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for environment in var.environments : "${var.state_bucket_arn}/${environment}/terraform.tfstate.tflock"]
  }
  statement {
    actions = [
      "autoscaling:Describe*", "ec2:Describe*", "ecs:Describe*", "ecs:List*",
      "logs:Describe*", "logs:ListTagsForResource", "logs:ListTagsLogGroup",
    ]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:DescribeRepositories", "ecr:GetLifecyclePolicy", "ecr:ListTagsForResource"]
    resources = local.repository_arns
  }
}

# apply는 프로젝트 서비스의 변경 권한을 넓게 가진다. state·ECR·PassRole만 대상 제한을 둔다.
# 비용 상한은 IAM에 두지 않으며 Budget은 알림만 보낸다.
data "aws_iam_policy_document" "apply" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = [for environment in var.environments : "${var.state_bucket_arn}/${environment}/terraform.tfstate"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [for environment in var.environments : "${var.state_bucket_arn}/${environment}/terraform.tfstate.tflock"]
  }
  statement {
    actions   = ["autoscaling:*", "ec2:*", "ecs:*", "logs:*"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:CreateRepository", "ecr:DeleteLifecyclePolicy", "ecr:DeleteRepository",
      "ecr:DescribeRepositories", "ecr:GetLifecyclePolicy", "ecr:ListTagsForResource",
      "ecr:PutImageTagMutability", "ecr:PutLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource",
    ]
    resources = local.repository_arns
  }
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
}

# image는 main 브랜치에서만 수임하고, 두 저장소에 이미지 push만 할 수 있다.
data "aws_iam_policy_document" "image" {
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
    resources = local.repository_arns
  }
}

resource "aws_iam_role_policy" "github" {
  for_each = local.github_subjects
  name     = { plan = "terraform-plan-read", apply = "terraform-foundation-apply", image = "ecr-image-push" }[each.key]
  role     = aws_iam_role.github[each.key].name
  policy = {
    plan  = data.aws_iam_policy_document.plan.json
    apply = data.aws_iam_policy_document.apply.json
    image = data.aws_iam_policy_document.image.json
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

# preprod 호스트의 WireGuard peer 등록과 진단은 SSH 대신 SSM Run Command로 한다.
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

# apply 역할에 IAM 생성 권한을 주지 않도록 서비스 연결 역할은 bootstrap에서 미리 만든다.
resource "aws_iam_service_linked_role" "this" {
  for_each         = toset(["autoscaling.amazonaws.com", "ecs.amazonaws.com"])
  aws_service_name = each.value
}
