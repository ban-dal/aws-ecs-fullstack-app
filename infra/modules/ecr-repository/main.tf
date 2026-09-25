# 환경별 비공개 이미지 저장소다. 태그는 덮어쓸 수 없고, 최근 이미지 5개만 남긴다.
# 이미지가 남아 있으면 저장소를 지우지 않는다. push할 때의 스캔은 계정 단위
# 설정(modules/ecr-registry)이 맡는다. 이미지는 앱 저장소의 환경별 배포 역할만 올린다.
# 관리자 권한 사용자도 저장소 정책을 바꾸지 않고는 push할 수 없다.

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = var.name })
}

data "aws_iam_policy_document" "push" {
  statement {
    sid     = "PushOnlyFromDeployRole"
    effect  = "Deny"
    actions = ["ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.push_role_arn]
    }
  }
}

resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy     = data.aws_iam_policy_document.push.json
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the five most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
