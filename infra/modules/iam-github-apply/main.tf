# 환경별 서비스 기반 적용 역할이다. main 브랜치의 *-apply GitHub 환경만 신뢰한다.
# 자기 state key, 자기 ECR 저장소, Environment 태그가 같은 EC2 리소스, 이름이
# aws-fullstack-lab-<환경>-으로 시작하는 ECS·Auto Scaling 리소스와 자기 환경 로그 그룹만
# 만들고 바꾸고 지울 수 있다. ECS 역할은 bootstrap이 만든 자기 환경 역할만 넘긴다.

locals {
  role_names = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-apply" }

  ec2_arn_prefix         = "arn:aws:ec2:${var.region}:${var.account_id}"
  ecs_arn_prefix         = "arn:aws:ecs:${var.region}:${var.account_id}"
  autoscaling_arn_prefix = "arn:aws:autoscaling:${var.region}:${var.account_id}"

  # 서비스 기반 모듈이 태그와 함께 만드는 EC2 리소스다. 생성할 때 자기 환경의
  # Environment 태그가 있어야 하고, 이후 변경도 이 태그로 해당 환경에만 허용된다.
  # RunInstances는 Auto Scaling group이 호스트를 띄울 때 태그를 붙이는 경우다.
  foundation_create_actions = [
    "ec2:CreateInternetGateway",
    "ec2:CreateLaunchTemplate",
    "ec2:CreateRouteTable",
    "ec2:CreateSecurityGroup",
    "ec2:CreateSubnet",
    "ec2:CreateVpc",
    "ec2:RunInstances",
  ]

  # 호스트 비용의 상한이다. 다른 유형이 필요하면 비용을 검토하고 bootstrap PR로 바꾼다.
  host_instance_types = ["t4g.micro"]
}

data "aws_iam_policy_document" "assume" {
  for_each = var.environments

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

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${var.repository_subject}:environment:${each.key}-apply"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.environments

  name                 = local.role_names[each.key]
  assume_role_policy   = data.aws_iam_policy_document.assume[each.key].json
  permissions_boundary = var.boundary_arn
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "foundation-apply"
  }
}

data "aws_iam_policy_document" "permissions" {
  for_each = var.environments

  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [var.state_bucket_arn]
  }

  statement {
    sid       = "ReadWriteOwnState"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.state_bucket_arn}/${each.key}/terraform.tfstate"]
  }

  statement {
    sid       = "LockOwnState"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.state_bucket_arn}/${each.key}/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ReadFoundationNetwork"
    actions   = var.read_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
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
    sid = "CreateTaggedEc2Resources"
    actions = [
      "ec2:CreateInternetGateway",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
    ]
    resources = [
      "${local.ec2_arn_prefix}:internet-gateway/*",
      "${local.ec2_arn_prefix}:launch-template/*",
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
    sid = "ManageOwnEc2Resources"
    actions = [
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:CreateRoute",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteVpc",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable",
      "ec2:ModifyLaunchTemplate",
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
  # ManageOwnEc2Resources에서 여전히 태그로 검사한다.
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
    resources = [var.repository_arns[each.key]]
  }

  # 아래 네 statement는 호스트 실행 권한이다. Auto Scaling group을 만들거나 바꿀 때 EC2 Auto
  # Scaling은 호출자가 시작 템플릿으로 인스턴스를 실행할 수 있는지 확인하고, 실제 실행은
  # 서비스 연결 역할이 한다. 자기 환경의 시작 템플릿·서브넷·보안 그룹, Amazon이 소유한 AMI,
  # 정한 인스턴스 유형일 때만 허용한다.
  statement {
    sid     = "RunHostsInOwnNetwork"
    actions = ["ec2:RunInstances"]
    resources = [
      "${local.ec2_arn_prefix}:launch-template/*",
      "${local.ec2_arn_prefix}:security-group/*",
      "${local.ec2_arn_prefix}:subnet/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid       = "RunHostsFromAmazonImages"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:${var.region}::image/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:Owner"
      values   = ["amazon"]
    }
  }

  statement {
    sid       = "RunAllowedHostTypes"
    actions   = ["ec2:RunInstances"]
    resources = ["${local.ec2_arn_prefix}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:InstanceType"
      values   = local.host_instance_types
    }
  }

  statement {
    sid     = "RunHostVolumesAndInterfaces"
    actions = ["ec2:RunInstances"]
    resources = [
      "${local.ec2_arn_prefix}:network-interface/*",
      "${local.ec2_arn_prefix}:volume/*",
    ]
  }

  statement {
    sid       = "PassOwnHostRole"
    actions   = ["iam:PassRole"]
    resources = [var.host_role_arns[each.key]]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  statement {
    sid       = "PassOwnTaskExecutionRole"
    actions   = ["iam:PassRole"]
    resources = [var.execution_role_arns[each.key]]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "CreateOwnHostGroup"
    actions   = ["autoscaling:CreateAutoScalingGroup"]
    resources = ["${local.autoscaling_arn_prefix}:autoScalingGroup:*:autoScalingGroupName/aws-fullstack-lab-${each.key}-*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid = "ManageOwnHostGroup"
    actions = [
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:DeleteTags",
      "autoscaling:ResumeProcesses",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:SuspendProcesses",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = ["${local.autoscaling_arn_prefix}:autoScalingGroup:*:autoScalingGroupName/aws-fullstack-lab-${each.key}-*"]
  }

  # 서비스 ARN에는 클러스터 이름이 들어가므로 이름 패턴이 다른 환경 클러스터 안의 서비스도
  # 막는다.
  statement {
    sid     = "CreateOwnEcsResources"
    actions = ["ecs:CreateCluster", "ecs:CreateService"]
    resources = [
      "${local.ecs_arn_prefix}:cluster/aws-fullstack-lab-${each.key}-*",
      "${local.ecs_arn_prefix}:service/aws-fullstack-lab-${each.key}-*/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  # RegisterTaskDefinition은 리소스 수준 권한을 지원하지 않아 요청 태그로만 제한한다.
  # 이전 revision은 남기므로(skip_destroy) 등록 해제·삭제 권한은 주지 않는다.
  statement {
    sid       = "RegisterOwnTaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = [each.key]
    }
  }

  statement {
    sid = "ManageOwnEcsResources"
    actions = [
      "ecs:DeleteCluster",
      "ecs:DeleteService",
      "ecs:PutClusterCapacityProviders",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:UpdateCluster",
      "ecs:UpdateClusterSettings",
      "ecs:UpdateService",
    ]
    resources = [
      "${local.ecs_arn_prefix}:cluster/aws-fullstack-lab-${each.key}-*",
      "${local.ecs_arn_prefix}:service/aws-fullstack-lab-${each.key}-*/*",
      "${local.ecs_arn_prefix}:task-definition/aws-fullstack-lab-${each.key}-*:*",
    ]
  }

  statement {
    sid = "ManageOwnLogGroups"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DeleteRetentionPolicy",
      "logs:PutRetentionPolicy",
      "logs:TagLogGroup",
      "logs:TagResource",
      "logs:UntagLogGroup",
      "logs:UntagResource",
    ]
    resources = [var.log_group_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.environments

  name   = "terraform-foundation-apply"
  role   = aws_iam_role.this[each.key].name
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
