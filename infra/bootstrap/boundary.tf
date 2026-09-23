# 모든 GitHub OIDC 역할의 권한 상한이다. bootstrap 운영 역할은 그 역할들은 고칠
# 수 있지만 이 정책은 고치지 못한다. 그래서 역할 정책이나 신뢰 정책을 넓혀도
# IAM, STS, 프로젝트 state와 리전 밖의 리소스에는 닿지 못한다.
# 상한은 서비스 단위로만 두고, 액션 단위 제한은 역할 정책이 맡는다. 새 AWS
# 서비스를 추가하는 PR은 이 boundary도 넓히고 root로 적용한다.
# GitHub 역할이 다른 역할을 넘겨야 할 때(ECS 인스턴스·태스크 역할 등)는 그 역할을
# 여기 bootstrap에서 만들고, 그 ARN에 대한 iam:PassRole만 추가한다.
data "aws_iam_policy_document" "github_boundary" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid     = "UseEnvironmentState"
    actions = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = [
      for environment in local.environments :
      "${aws_s3_bucket.state.arn}/${environment}/*"
    ]
  }

  statement {
    sid       = "UseProjectRegionServices"
    actions   = ["ec2:*", "ecr:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

locals {
  github_boundary_name = "aws-fullstack-lab-github-boundary"
  # 이름으로 ARN을 만든다. boundary가 생기기 전에도 이를 참조하는 정책 JSON을
  # plan에서 읽을 수 있게 하기 위해서다.
  github_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${local.github_boundary_name}"
}

resource "aws_iam_policy" "github_boundary" {
  name        = local.github_boundary_name
  description = "Permissions boundary for aws-fullstack-lab GitHub OIDC roles"
  policy      = data.aws_iam_policy_document.github_boundary.json
}
