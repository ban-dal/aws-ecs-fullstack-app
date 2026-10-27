# bootstrap에서 옮겨 온 앱 배포 역할을 가져온다(infra/bootstrap/removed.tf). 적용이 끝나면 다음 PR에서 지운다.
import {
  to = module.app_deploy.aws_iam_role.this
  id = "aws-fullstack-lab-app-preprod"
}

import {
  to = module.app_deploy.aws_iam_role_policy.deploy
  id = "aws-fullstack-lab-app-preprod:preprod-app-deploy"
}
