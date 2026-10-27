# 앱 저장소 GitHub Actions가 한 환경에 배포할 때 수임하는 역할이다. 환경 루트가 서비스
# 리소스와 함께 관리하므로, 배포에 필요한 권한이 바뀌어도 그 환경 루트 하나만 적용한다.
# OIDC 제공자는 계정에 하나뿐이라 bootstrap의 modules/iam에 둔다.
locals {
  # 앱 저장소의 immutable owner/repository ID다. 저장소가 이전·재생성되면 다시 확인한다.
  app_repository_subject = "repo:ban-dal@46153202/aws-ecs-fullstack-web@1386828063"

  name        = "aws-fullstack-lab-app-${var.environment}"
  cluster     = "aws-fullstack-lab-${var.environment}-cluster"
  service_arn = "arn:aws:ecs:${var.region}:${var.account_id}:service/${local.cluster}/web"
  # modules/iam의 공통 ECS 실행 역할이다.
  execution_role_arn = "arn:aws:iam::${var.account_id}:role/aws-fullstack-lab-ecs-task-execution"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.app_repository_subject}:${var.github_subject_suffix}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
  tags                 = { Project = "aws-fullstack-lab", Purpose = "app-${var.environment}" }
}

# 환경의 ECR 저장소에 이미지를 올리고 해당 ECS 서비스만 갱신한다.
data "aws_iam_policy_document" "deploy" {
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
    resources = ["arn:aws:ecr:${var.region}:${var.account_id}:repository/aws-fullstack-lab-${var.environment}-web"]
  }
  statement {
    actions   = ["ecs:DescribeServices", "ecs:UpdateService"]
    resources = [local.service_arn]
  }
  statement {
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"]
  }
  statement {
    # 배포 workflow가 자동 롤백 원인을, prod 롤백 workflow가 직전 성공 배포의 이미지를 찾는다.
    actions = ["ecs:ListServiceDeployments", "ecs:DescribeServiceDeployments", "ecs:DescribeServiceRevisions"]
    resources = [
      local.service_arn,
      "arn:aws:ecs:${var.region}:${var.account_id}:service-deployment/${local.cluster}/web/*",
      "arn:aws:ecs:${var.region}:${var.account_id}:service-revision/${local.cluster}/web/*",
    ]
  }
  statement {
    actions   = ["ecs:RegisterTaskDefinition", "ecs:TagResource"]
    resources = ["arn:aws:ecs:${var.region}:${var.account_id}:task-definition/aws-fullstack-lab-${var.environment}-web:*"]
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
  dynamic "statement" {
    for_each = var.read_alb_target_health ? [1] : []
    content {
      # DescribeTargetHealth는 리소스 ARN 범위 지정을 지원하지 않는다.
      actions   = ["elasticloadbalancing:DescribeTargetHealth"]
      resources = ["*"]
    }
  }
  dynamic "statement" {
    for_each = var.ecs_infrastructure_role_arn == null ? [] : [1]
    content {
      # blue/green 서비스의 UpdateService는 서비스에 설정된 인프라 역할을 ECS에 다시 넘긴다.
      actions   = ["iam:PassRole"]
      resources = [var.ecs_infrastructure_role_arn]
      condition {
        test     = "StringEquals"
        variable = "iam:PassedToService"
        values   = ["ecs.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "${var.environment}-app-deploy"
  role   = aws_iam_role.this.name
  policy = data.aws_iam_policy_document.deploy.json
}
