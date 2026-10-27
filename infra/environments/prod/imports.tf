# bootstrap에서 옮겨 온 앱 배포 역할과 ECS 인프라 역할을 가져온다(infra/bootstrap/removed.tf).
# 적용이 끝나면 다음 PR에서 지운다.
import {
  to = module.app_deploy.aws_iam_role.this
  id = "aws-fullstack-lab-app-prod"
}

import {
  to = module.app_deploy.aws_iam_role_policy.deploy
  id = "aws-fullstack-lab-app-prod:prod-app-deploy"
}

import {
  to = module.web.aws_iam_role.ecs_infrastructure
  id = "aws-fullstack-lab-ecs-infrastructure"
}

import {
  to = module.web.aws_iam_role_policy_attachment.ecs_infrastructure
  id = "aws-fullstack-lab-ecs-infrastructure/arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}
