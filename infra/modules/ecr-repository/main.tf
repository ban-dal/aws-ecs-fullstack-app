# 환경별 비공개 이미지 저장소다. 태그는 덮어쓸 수 없고, 최근 이미지 5개만 남긴다.
# 이미지가 남아 있으면 저장소를 지우지 않는다. push할 때의 스캔은 계정 단위
# 설정(modules/ecr-registry)이 맡는다.

resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, { Name = var.name })
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
