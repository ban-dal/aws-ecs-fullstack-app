# Upper limit for every GitHub OIDC role. The bootstrap operator can edit those
# roles but not this policy, so a widened role policy or trust policy still
# cannot reach IAM, STS, or resources outside the project state and region.
# Limits are per service; the role policies narrow them to actions. A pull
# request that adds an AWS service widens this boundary and is applied by root.
# When a GitHub role must pass a role (ECS instance or task roles), create that
# role here in bootstrap and add iam:PassRole for its ARN only.
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
  # Built from the name so dependent policies stay readable in plans before the
  # boundary exists.
  github_boundary_arn = "arn:aws:iam::${local.account_id}:policy/${local.github_boundary_name}"
}

resource "aws_iam_policy" "github_boundary" {
  name        = local.github_boundary_name
  description = "Permissions boundary for aws-fullstack-lab GitHub OIDC roles"
  policy      = data.aws_iam_policy_document.github_boundary.json
}
