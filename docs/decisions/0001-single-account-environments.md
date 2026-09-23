# 0001. 한 AWS 계정 안에서 환경을 논리적으로 분리

- 상태: 채택
- 관련 PR: [#1](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/1), [#3](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/3), [#6](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/6)

## 맥락

`preprod`와 `prod`는 실제 고객 환경이 아니라 AI 작업과 학습을 위한 두 실험 환경이다. 계정을 분리하려면 AWS Organizations가 필요한데, 현재 Free plan 계정이 Organizations에 가입하면 크레딧이 즉시 만료되고 유료 플랜으로 전환된다.

## 결정

한 계정 안에서 환경을 나눈다. 환경마다 S3 state key(`<environment>/terraform.tfstate`), VPC CIDR(`10.60.0.0/16`, `10.61.0.0/16`), 리소스 이름 접두사(`aws-fullstack-lab-<environment>`), GitHub 환경, OIDC 역할을 따로 둔다.

## 결과와 제약

IAM, 서비스 한도, 계정 수준 장애는 두 환경이 공유한다. 환경 간 권한 격리는 역할 정책과 태그 조건([0005](0005-github-role-boundary.md))에 의존한다.

## 다시 볼 조건

실제 사용자 데이터를 다루거나, Free plan 기간이 끝나거나, 환경 간 IAM 격리가 필요해지면 계정 분리를 검토한다.
