# 환경별 서비스 기반 적용 역할이다. main 브랜치의 *-apply GitHub 환경만 신뢰한다.
#
# 권한은 넓게 주고 치명적인 것만 막는다. 프로젝트가 쓰는 서비스는 이 리전에서 서비스
# 단위로 허용하고, 아래를 명시적으로 거부한다.
# - 다른 환경의 리소스: Environment 태그가 다른 환경이거나 이름이 다른 환경 접두사인 리소스
# - Environment 태그 제거와 다른 환경 태그 붙이기
# - 비용 상한을 넘는 호스트(유형·볼륨 크기·개수), 장기 약정이나 큰 고정 비용
# - 계정 전체 설정 변경과 계정 밖으로의 공개 공유
# 액션을 하나씩 허용하면 정책이 역할당 inline 한도(10,240자)에 닿고, 빠진 액션마다 root
# 적용이 필요했기 때문이다.
#
# 태그가 없는 리소스는 두 환경이 모두 바꿀 수 있다. 서비스 기반 모듈은 모든 리소스에
# Environment 태그를 붙이고, 삭제와 교체는 적용 workflow 검사(scripts/tfplan.sh)가 막는다.
# IAM·STS와 리전 밖은 boundary가 막는다. state, ECR 저장소, ECS 역할 PassRole은 자기
# 환경 것만 좁혀 허용한다.

locals {
  role_names         = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-apply" }
  other_environments = { for environment in var.environments : environment => sort(setsubtract(var.environments, [environment])) }

  ec2_arn_prefix = "arn:aws:ec2:${var.region}:${var.account_id}"

  # 환경 안에서 서비스 단위로 허용하는 서비스다. 새 서비스는 boundary와 함께 추가한다.
  service_actions = ["autoscaling:*", "ec2:*", "ecs:*", "logs:*"]

  # ARN에 이름이 들어가는 리소스다. 태그가 없거나 태그 조건을 지원하지 않는 요청도 이름으로
  # 다른 환경을 막는다. EC2 리소스 ARN에는 이름이 없어 태그로만 막는다.
  other_environment_named_arns = {
    for environment in var.environments : environment => flatten([
      for other in local.other_environments[environment] : [
        "arn:aws:autoscaling:${var.region}:${var.account_id}:autoScalingGroup:*:autoScalingGroupName/aws-fullstack-lab-${other}-*",
        "arn:aws:ecs:${var.region}:${var.account_id}:cluster/aws-fullstack-lab-${other}-*",
        "arn:aws:ecs:${var.region}:${var.account_id}:container-instance/aws-fullstack-lab-${other}-*/*",
        "arn:aws:ecs:${var.region}:${var.account_id}:service/aws-fullstack-lab-${other}-*/*",
        "arn:aws:ecs:${var.region}:${var.account_id}:task/aws-fullstack-lab-${other}-*/*",
        "arn:aws:ecs:${var.region}:${var.account_id}:task-definition/aws-fullstack-lab-${other}-*",
        "arn:aws:logs:${var.region}:${var.account_id}:log-group:aws-fullstack-lab-${other}-*",
      ]
    ])
  }

  # 호스트 비용의 상한이다. 바꾸려면 비용을 검토하고 bootstrap PR로 바꾼다. 볼륨 크기는
  # ECS 최적화 AMI의 루트 볼륨 크기, 개수는 prod의 두 AZ 호스트다.
  host_instance_types = ["t4g.micro"]
  host_volume_max_gib = 30
  host_max_count      = 2

  # 장기 약정이나 큰 고정 비용을 만드는 액션이다. 인스턴스 속성과 볼륨 변경은 위 상한을
  # 우회할 수 있다.
  denied_cost_actions = [
    "ec2:AllocateHosts",
    "ec2:CreateCapacityReservation",
    "ec2:CreateCapacityReservationFleet",
    "ec2:CreateFleet",
    "ec2:CreateNatGateway",
    "ec2:CreateTransitGateway",
    "ec2:ModifyInstanceAttribute",
    "ec2:ModifyVolume",
    "ec2:Purchase*",
    "ec2:RequestSpotFleet",
    "ec2:RequestSpotInstances",
  ]

  # 한 환경의 적용이 계정 전체 설정을 바꾸거나 리소스를 계정 밖에 공개하는 액션이다.
  denied_account_actions = [
    "ec2:DisableEbsEncryptionByDefault",
    "ec2:DisableImageBlockPublicAccess",
    "ec2:DisableSnapshotBlockPublicAccess",
    "ec2:EnableSerialConsoleAccess",
    "ec2:ModifyImageAttribute",
    "ec2:ModifyInstanceMetadataDefaults",
    "ec2:ModifySnapshotAttribute",
    "ecs:DeleteAccountSetting",
    "ecs:PutAccountSetting",
    "ecs:PutAccountSettingDefault",
    "logs:DeleteAccountPolicy",
    "logs:PutAccountPolicy",
    "logs:PutResourcePolicy",
  ]
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
    sid       = "UseProjectServices"
    actions   = local.service_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # ECR은 서비스 단위로 열지 않는다. 이미지 push는 image 역할만 한다.
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

  # 부모 리소스도 검사하므로, 다른 환경 VPC 안의 서브넷이나 다른 환경 서브넷의 호스트도
  # 막힌다.
  statement {
    sid       = "DenyOtherEnvironmentResources"
    effect    = "Deny"
    actions   = local.service_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Environment"
      values   = local.other_environments[each.key]
    }
  }

  statement {
    sid       = "DenyOtherEnvironmentTags"
    effect    = "Deny"
    actions   = local.service_actions
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Environment"
      values   = local.other_environments[each.key]
    }
  }

  # 태그를 지우면 그 리소스는 다른 환경도 바꿀 수 있게 된다.
  statement {
    sid    = "DenyEnvironmentTagRemoval"
    effect = "Deny"
    actions = [
      "autoscaling:DeleteTags",
      "ec2:DeleteTags",
      "ecs:UntagResource",
      "logs:UntagLogGroup",
      "logs:UntagResource",
    ]
    resources = ["*"]

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Environment"]
    }
  }

  statement {
    sid       = "DenyOtherEnvironmentNames"
    effect    = "Deny"
    actions   = local.service_actions
    resources = local.other_environment_named_arns[each.key]
  }

  statement {
    sid       = "DenyOtherHostTypes"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["${local.ec2_arn_prefix}:instance/*"]

    condition {
      test     = "StringNotEquals"
      variable = "ec2:InstanceType"
      values   = local.host_instance_types
    }
  }

  statement {
    sid       = "DenyLargeVolumes"
    effect    = "Deny"
    actions   = ["ec2:CreateVolume", "ec2:RunInstances"]
    resources = ["${local.ec2_arn_prefix}:volume/*"]

    condition {
      test     = "NumericGreaterThan"
      variable = "ec2:VolumeSize"
      values   = [tostring(local.host_volume_max_gib)]
    }
  }

  # Marketplace AMI는 소프트웨어 요금이 따로 붙는다.
  statement {
    sid       = "DenyNonAmazonImages"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:${var.region}::image/*"]

    condition {
      test     = "StringNotEquals"
      variable = "ec2:Owner"
      values   = ["amazon"]
    }
  }

  statement {
    sid       = "DenyTooManyHosts"
    effect    = "Deny"
    actions   = ["autoscaling:CreateAutoScalingGroup", "autoscaling:UpdateAutoScalingGroup"]
    resources = ["*"]

    condition {
      test     = "NumericGreaterThan"
      variable = "autoscaling:MaxSize"
      values   = [tostring(local.host_max_count)]
    }
  }

  statement {
    sid       = "DenyCostlyCommitments"
    effect    = "Deny"
    actions   = local.denied_cost_actions
    resources = ["*"]
  }

  statement {
    sid       = "DenyAccountSettings"
    effect    = "Deny"
    actions   = local.denied_account_actions
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.environments

  name   = "terraform-foundation-apply"
  role   = aws_iam_role.this[each.key].name
  policy = data.aws_iam_policy_document.permissions[each.key].json
}
