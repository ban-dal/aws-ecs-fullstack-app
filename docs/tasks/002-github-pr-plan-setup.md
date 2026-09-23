# Task 002: GitHub PR plan 환경 구성

| 항목 | 값 |
| --- | --- |
| PR | [#2 · GitHub PR plan 환경 구성](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/2) |
| 작업 브랜치 | `feat/github-pr-plan-setup` |
| 상태 | 완료: PR merge |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | 2026-09-23 · `6f680eb45d1baa578776bdd1eb620700298dee3f` |

## 목표와 완료 기준

Task 001에서 만든 GitHub OIDC plan 역할을 실제 PR에서 사용한다. `preprod`와 `prod`가 서로 다른 S3 state key를 사용하고, 예상 AWS 계정에서 Terraform plan이 실행되는지 확인한다.

완료 기준은 GitHub 환경 보호 설정, bootstrap output에 맞는 저장소 변수, 같은 저장소 PR에서 두 plan 작업의 성공, 검증 기록, PR merge다. plan 역할은 state 읽기와 잠금에만 사용한다.

## 작업 내용과 결정

- `preprod-plan`, `prod-plan` GitHub 환경을 만들고 `ban-dal`을 필수 승인자로 지정했다. 사용자 선택에 따라 환경 작업의 자기 승인을 허용했다(`prevent_self_review=false`). PR 자체의 Approve와 환경 배포 승인은 서로 다른 기능이다.
- `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_ACCOUNT_ID`, `AWS_REGION` 저장소 변수를 Task 001의 Terraform output과 대조해 등록하고 다시 읽어 확인했다. AWS 키·토큰은 GitHub에 저장하지 않았다.
- PR 검증 결과와 이후 재구성 방법을 `docs/operations.md`와 이 문서에 기록했다.

### 확인한 bootstrap output

| 저장소 변수 | 확인한 값 |
| --- | --- |
| `TF_STATE_BUCKET` | `aws-ecs-fullstack-app` |
| `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::065768154598:role/aws-fullstack-lab-plan` |
| `AWS_ACCOUNT_ID` | `065768154598` |
| `AWS_REGION` | `ap-northeast-2` |

2026-09-23에 원격 Terraform state의 output과 대조했고, 두 환경을 먼저 설정한 뒤 네 저장소 변수를 등록했다.

### 환경 승인 정책 결정

GitHub의 **배포 환경 승인**은 PR Approve와 별개다. 1인 운영을 위해 사용자가 `ban-dal` 계정의 수동 환경 승인을 선택했다. 두 환경 모두 `ban-dal`을 필수 승인자로 설정하고 `prevent_self_review=false`로 확인했다. 각 plan은 사람이 승인해야 시작하지만 독립된 두 번째 검토자는 없다. [GitHub 환경 보호 규칙](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)을 참고한다.

환경 보호 규칙을 먼저 설정하고 저장소 변수를 등록했다. 변수만 먼저 등록하면 PR의 AWS plan이 승인 규칙 없이 실행될 수 있기 때문이다.

## 재구성 절차

1. [Task 001](001-terraform-foundation.md)의 bootstrap 적용과 S3 state 이전을 확인한다.
2. [운영 가이드의 GitHub 설정](../operations.md#2-github-설정)에 따라 두 환경의 보호 규칙과 네 저장소 변수를 설정한다.
3. 같은 저장소 PR에서 GitHub Actions의 `preprod`·`prod` plan 결과, AWS 계정 ID, state key와 변경 범위를 확인한다. 환경 승인 단계가 있으면 승인 후 결과를 기록한다.

## 검증과 운영 영향

- [PR #2 Terraform 실행 35823513637](https://github.com/ban-dal/aws-ecs-fullstack-app/actions/runs/35823513637)에서 `validate`, `plan (preprod)`, `plan (prod)`가 모두 성공했다. 앱 CI도 성공했다.
- `ban-dal`이 두 환경 작업을 수동 승인한 뒤 GitHub OIDC로 plan 역할을 맡았다. 두 작업 모두 S3 backend를 초기화하고 AWS 계정 `065768154598`을 확인했다.
- `preprod/terraform.tfstate`와 `prod/terraform.tfstate`를 각각 backend key로 지정했다. plan 결과는 환경별 `plan_identity` 출력값 추가뿐이며 실제 AWS 인프라 생성·변경·삭제는 없었다. `apply`는 실행하지 않았다.
- 이 Task의 GitHub 설정 자체는 AWS 리소스를 생성하지 않는다. plan이 사용하는 S3 요청과 잠금 파일에는 사용량에 따른 비용이 생길 수 있다.

## 남은 사항과 다음 Task

[Task 003](003-service-foundation.md)에서 VPC·서브넷·보안 그룹·ECR 기반을 분리해 선언한다. ECS/EC2와 공개 앱 경로는 비용과 배포 순서를 검토한 뒤 후속 Task로 진행한다.
