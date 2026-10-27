# 계정에 하나뿐인 IAM을 관리한다: GitHub OIDC 제공자, 사람의 MFA 운영 역할, 두 환경이 공유하는
# ECS 호스트·태스크 실행 역할. 환경별 앱 배포 역할(modules/iam-app-deploy)과 prod ECS 인프라
# 역할(modules/ecs-prod-web)은 각 환경 루트가 서비스 리소스와 함께 관리한다.
locals {
  repository_arns = [for environment in var.environments :
  "arn:aws:ecr:${var.region}:${var.account_id}:repository/aws-fullstack-lab-${environment}-web"]
  log_group_arns = [for environment in var.environments :
  "arn:aws:logs:${var.region}:${var.account_id}:log-group:aws-fullstack-lab-${environment}-*"]

  host_role_arn      = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-host"
  execution_role_arn = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-task-execution"
}

# 앱 저장소의 배포 역할(modules/iam-app-deploy)이 이 제공자를 신뢰한다.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
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

# 실험 계정의 모든 Terraform 루트를 적용한다. 이 역할은 계정 관리자 권한이므로 MFA를 필수로 둔다.
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
