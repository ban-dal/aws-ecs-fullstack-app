# 환경별 이미지 push 역할이다. main 브랜치에서 실행된 workflow만 신뢰하고, 자기 환경의
# ECR 저장소에 이미지를 올리는 권한만 가진다. main에 merge된 코드로 이미지를 한 번
# 빌드해 두 환경 저장소에 같은 태그(commit SHA)로 올리므로, prod에는 preprod와 같은
# 커밋의 이미지가 배포된다. 저장소를 만들거나 지우는 권한은 apply 역할에만 있다.

locals {
  role_names = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-image" }
}

data "aws_iam_policy_document" "assume" {
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

    # 환경을 쓰지 않는 main 브랜치 작업의 subject다. PR 작업은 이 값을 받지 못한다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.repository_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.environments

  name                 = local.role_names[each.key]
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.boundary_arn
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "image-push"
  }
}

data "aws_iam_policy_document" "permissions" {
  for_each = var.environments

  # 레지스트리 로그인 토큰은 리소스 수준 권한을 지원하지 않는다.
  statement {
    sid       = "GetRegistryLoginToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid = "PushToOwnRepository"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [var.repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.environments

  name   = "ecr-image-push"
  role   = aws_iam_role.this[each.key].name
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
