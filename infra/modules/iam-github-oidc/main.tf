# GitHub Actions가 AWS에 들어오는 입구다. GitHub OIDC 제공자와, 이 제공자를 신뢰하는
# 모든 GitHub 역할에 붙는 permissions boundary를 둔다.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# 모든 GitHub OIDC 역할의 권한 상한이다. bootstrap 운영 역할은 그 역할들은 고칠
# 수 있지만 이 정책은 고치지 못한다. 그래서 역할 정책이나 신뢰 정책을 넓혀도
# IAM, STS, 프로젝트 state와 리전 밖의 리소스에는 닿지 못한다.
# 상한은 서비스 단위로만 두고, 액션 단위 제한은 역할 정책이 맡는다. 새 AWS
# 서비스를 추가하는 PR은 이 boundary도 넓히고 root로 적용한다.
# GitHub 역할이 다른 역할을 넘겨야 할 때(ECS 인스턴스·태스크 역할 등)는 그 역할을
# bootstrap에서 만들고, 그 ARN에 대한 iam:PassRole만 추가한다.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid     = "UseEnvironmentState"
    actions = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = [
      for environment in var.environments :
      "${var.state_bucket_arn}/${environment}/*"
    ]
  }

  statement {
    sid       = "UseProjectRegionServices"
    actions   = ["autoscaling:*", "ec2:*", "ecr:*", "ecs:*", "logs:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # 서비스에 넘길 수 있는 역할은 bootstrap이 만든 ECS 역할뿐이다. 어느 환경 역할을 어느
  # 서비스에 넘기는지는 역할 정책이 제한한다.
  statement {
    sid       = "PassProjectServiceRoles"
    actions   = ["iam:PassRole"]
    resources = var.passable_role_arns
  }
}

resource "aws_iam_policy" "boundary" {
  name        = var.boundary_name
  description = "Permissions boundary for aws-fullstack-lab GitHub OIDC roles"
  policy      = data.aws_iam_policy_document.boundary.json
}
