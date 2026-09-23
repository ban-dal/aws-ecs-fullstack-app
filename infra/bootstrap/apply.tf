locals {
  ec2_arn_prefix = "arn:aws:ec2:${var.aws_region}:${local.account_id}"

  # Resources the foundation module creates. Each must carry the environment's
  # Environment tag at creation, which later limits changes to that environment.
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

  # The parent VPC is authorized separately so a tagged child cannot be placed
  # in another environment's VPC.
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

  # Security group rules are untagged child resources; the parent group is
  # still checked by ManageOwnNetwork.
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
