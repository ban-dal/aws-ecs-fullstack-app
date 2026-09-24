# 환경별 ECS 호스트 역할(인스턴스 프로파일)과 태스크 실행 역할이다. GitHub apply 역할은
# 이 역할을 만들거나 고치지 못하고, 자기 환경 역할을 정해진 서비스에 넘기기(iam:PassRole)만
# 한다. 운영 역할도 읽기만 하고 변경은 root로 적용한다. 운영 역할이 이 역할을 고칠 수
# 있으면, apply 역할이 이 역할을 넘긴 호스트를 통해 boundary 밖의 권한을 얻을 수 있다.
#
# 역할과 인스턴스 프로파일 이름은 infra/environments/<환경>의 ECS 모듈이 이름으로 참조한다.
# 앱은 AWS API를 호출하지 않으므로 태스크 역할은 두지 않는다.

locals {
  host_role_names      = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-ecs-host" }
  execution_role_names = { for environment in var.environments : environment => "aws-fullstack-lab-${environment}-ecs-task-execution" }
}

data "aws_iam_policy_document" "host_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "host" {
  for_each = var.environments

  name                 = local.host_role_names[each.key]
  assume_role_policy   = data.aws_iam_policy_document.host_assume.json
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "ecs-host"
  }
}

# ECS agent가 클러스터에 등록하고 태스크 상태를 보고하는 권한이다. agent가 쓰는 API는
# 버전마다 바뀌므로 AWS 관리형 정책을 쓴다. 이 정책은 클러스터를 구분하지 않으므로 한
# 환경의 호스트가 다른 환경 클러스터에 등록할 수는 있다. 호스트가 들어갈 클러스터는 자기
# 환경 시작 템플릿의 user data가 정한다.
resource "aws_iam_role_policy_attachment" "host" {
  for_each = var.environments

  role       = aws_iam_role.host[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "host" {
  for_each = var.environments

  name = local.host_role_names[each.key]
  role = aws_iam_role.host[each.key].name

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "ecs-host"
  }
}

# ECS가 태스크를 시작할 때 이미지를 받고 로그 스트림을 만드는 역할이다. 다른 계정의
# ECS가 이 역할을 쓰지 못하도록 요청한 계정과 ARN을 확인한다.
data "aws_iam_policy_document" "execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${var.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  for_each = var.environments

  name                 = local.execution_role_names[each.key]
  assume_role_policy   = data.aws_iam_policy_document.execution_assume.json
  max_session_duration = 3600

  tags = {
    Project     = "aws-fullstack-lab"
    Environment = each.key
    Purpose     = "ecs-task-execution"
  }
}

# AWS 관리형 AmazonECSTaskExecutionRolePolicy는 모든 저장소와 로그 그룹을 허용하므로 쓰지
# 않고, 자기 환경 저장소 pull과 자기 환경 로그 쓰기만 준다.
data "aws_iam_policy_document" "execution" {
  for_each = var.environments

  statement {
    sid       = "GetRegistryLoginToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullOwnImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.repository_arns[each.key]]
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [var.log_group_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "execution" {
  for_each = var.environments

  name   = "ecs-task-execution"
  role   = aws_iam_role.execution[each.key].name
  policy = data.aws_iam_policy_document.execution[each.key].json
}
