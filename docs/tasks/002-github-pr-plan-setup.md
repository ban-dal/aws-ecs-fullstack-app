# Task 002: GitHub PR plan 환경 구성

| 항목 | 값 |
| --- | --- |
| PR | 생성 후 연결 |
| 작업 브랜치 | `feat/github-pr-plan-setup` |
| 상태 | 진행 중 |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 001에서 만든 GitHub OIDC plan 역할을 실제 PR에서 사용한다. `preprod`와 `prod`가 서로 다른 S3 state key를 사용하고, 예상 AWS 계정에서 Terraform plan이 실행되는지 확인한다.

완료 기준은 GitHub 환경 보호 설정, bootstrap output에 맞는 저장소 변수, 같은 저장소 PR에서 두 plan 작업의 성공, 검증 기록, PR merge다. plan 역할은 state 읽기와 잠금에만 사용한다.

## 작업 내용과 결정

- `preprod-plan`, `prod-plan` GitHub 환경을 만들고 수동 승인 규칙을 설정한다. 1인 저장소이므로 환경 배포의 자기 승인 허용 여부를 먼저 결정한다. PR 자체의 Approve와 환경 배포 승인은 서로 다른 기능이다.
- `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_ACCOUNT_ID`, `AWS_REGION` 저장소 변수를 Task 001의 Terraform output과 대조해 등록한다. AWS 키·토큰은 GitHub에 저장하지 않는다.
- PR 검증 결과와 이후 재구성 방법을 `docs/operations.md`와 이 문서에 기록한다.

### 확인한 bootstrap output

| 저장소 변수 | 확인한 값 |
| --- | --- |
| `TF_STATE_BUCKET` | `aws-ecs-fullstack-app` |
| `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::065768154598:role/aws-fullstack-lab-plan` |
| `AWS_ACCOUNT_ID` | `065768154598` |
| `AWS_REGION` | `ap-northeast-2` |

2026-09-23에 원격 Terraform state의 output과 대조했다. 현재 GitHub 환경과 저장소 변수는 모두 미설정이다.

### 환경 승인 정책 결정

GitHub의 **배포 환경 승인**은 PR Approve와 별개다. 환경의 `prevent_self_review=false`는 작업을 시작한 계정도 그 환경 작업을 승인하도록 허용한다. 1인 운영에 편리하지만 독립된 두 번째 검토자가 없으므로 명시적 선택이 필요하다. `prevent_self_review=true`를 유지하려면 작업을 시작한 계정 외에 신뢰할 수 있는 검토자가 필요하다. [GitHub 환경 보호 규칙](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)을 참고한다.

환경 승인 정책이 정해지기 전에는 환경과 저장소 변수를 생성하지 않는다. 변수만 먼저 등록하면 PR의 AWS plan이 승인 규칙 없이 실행될 수 있기 때문이다.

## 재구성 절차

1. [Task 001](001-terraform-foundation.md)의 bootstrap 적용과 S3 state 이전을 확인한다.
2. [운영 가이드의 GitHub 설정](../operations.md#2-github-설정)에 따라 두 환경의 보호 규칙과 네 저장소 변수를 설정한다.
3. 같은 저장소 PR에서 GitHub Actions의 `preprod`·`prod` plan 결과, AWS 계정 ID, state key와 변경 범위를 확인한다. 환경 승인 단계가 있으면 승인 후 결과를 기록한다.

## 검증과 운영 영향

- 아직 실제 PR plan 검증 전이다. 환경 승인 정책을 결정하고 결과를 확인한 뒤 여기에 기록한다.
- 이 Task의 GitHub 설정 자체는 AWS 리소스를 생성하지 않는다. plan이 사용하는 S3 요청과 잠금 파일에는 사용량에 따른 비용이 생길 수 있다.

## 남은 사항과 다음 Task

다음 Task 후보는 VPC·서브넷·보안 그룹·ECR·ECS/EC2 등 서비스 인프라를 비용과 종료 절차까지 포함해 설계·구현하는 작업이다.
