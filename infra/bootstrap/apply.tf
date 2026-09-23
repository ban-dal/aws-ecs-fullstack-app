locals {
  ec2_arn_prefix = "arn:aws:ec2:${var.aws_region}:${local.account_id}"

  # 서비스 기반 모듈이 만드는 리소스다. 생성할 때 자기 환경의 Environment 태그가
  # 있어야 하고, 이후 변경도 이 태그로 해당 환경에만 허용된다.
  foundation_create_actions = [
    "ec2:CreateInternetGateway",
    "ec2:CreateRouteTable",
    "ec2:CreateSecurityGroup",
    "ec2:CreateSubnet",
    "ec2:CreateVpc",
  ]
}

data "aws_iam_policy_document" "foundation_apply_assume" {
  for_each = local.environments

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
      values   = ["${var.github_repository_subject}:environment:${each.key}-apply"]
    }
  }
}

resource "aws_iam_role" "foundation_apply" {
  for_each = local.environments

  name                 = "aws-fullstack-lab-${each.key}-apply"
  assume_role_policy   = data.aws_iam_policy_document.foundation_apply_assume[each.key].json
  permissions_boundary = local.github_boundary_arn
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "foundation-apply"
  }

  depends_on = [aws_iam_policy.github_boundary]
}

data "aws_iam_policy_document" "foundation_apply" {
  for_each = local.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid       = "ReadWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate"]
  }

  statement {
    sid       = "LockOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/${each.key}/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ReadFoundationNetwork"
    actions   = local.foundation_read_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid       = "CreateTaggedVpc"
    actions   = ["ec2:CreateVpc"]
    resources = ["${local.ec2_arn_prefix}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid = "CreateTaggedNetworkResources"
    actions = [
      "ec2:CreateInternetGateway",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
    ]
    resources = [
      "${local.ec2_arn_prefix}:internet-gateway/*",
      "${local.ec2_arn_prefix}:route-table/*",
      "${local.ec2_arn_prefix}:security-group/*",
      "${local.ec2_arn_prefix}:subnet/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  # 부모 VPC를 따로 검사해, 자기 태그를 붙인 하위 리소스라도 다른 환경의 VPC
  # 안에는 만들지 못하게 한다.
  statement {
    sid = "CreateInOwnVpc"
    actions = [
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
    ]
    resources = ["${local.ec2_arn_prefix}:vpc/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "TagOnCreate"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.ec2_arn_prefix}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = [for action in local.foundation_create_actions : trimprefix(action, "ec2:")]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid = "ManageOwnNetwork"
    actions = [
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateRoute",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteVpc",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySecurityGroupRules",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["${local.ec2_arn_prefix}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  # 보안 그룹 규칙은 태그가 없는 하위 리소스다. 부모 보안 그룹은
  # ManageOwnNetwork에서 여전히 태그로 검사한다.
  statement {
    sid = "ManageRulesOfOwnSecurityGroups"
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:ModifySecurityGroupRules",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
    ]
    resources = ["${local.ec2_arn_prefix}:security-group-rule/*"]
  }

  statement {
    sid       = "RetagOwnNetwork"
    actions   = ["ec2:CreateTags"]
    resources = ["${local.ec2_arn_prefix}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "StringEqualsIfExists"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "UntagOwnNetwork"
    actions   = ["ec2:DeleteTags"]
    resources = ["${local.ec2_arn_prefix}:*/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }

    condition {
      test     = "ForAllValues:StringNotEquals"
      variable = "aws:TagKeys"
      values   = ["Environment"]
    }
  }

  statement {
    sid = "ManageOwnRepository"
    actions = [
      "ecr:CreateRepository",
      "ecr:DeleteLifecyclePolicy",
      "ecr:DeleteRepository",
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:ListTagsForResource",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = [local.web_repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "foundation_apply" {
  for_each = local.environments

  name   = "terraform-foundation-apply"
  role   = aws_iam_role.foundation_apply[each.key].name
  policy = data.aws_iam_policy_document.foundation_apply[each.key].json
}

output "foundation_apply_role_arns" {
  value = { for environment, role in aws_iam_role.foundation_apply : environment => role.arn }
}
