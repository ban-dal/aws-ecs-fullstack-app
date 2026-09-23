# Task 001: Terraform 기반과 PR 검증

| 항목 | 값 |
| --- | --- |
| PR | [#1 · Terraform state·OIDC 기반과 PR 검증 구성](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/1) |
| 작업 브랜치 | `feat/terraform-foundation` |
| 상태 | 진행 중: PR 열림 (2026-09-23 확인) |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Next.js 앱의 후속 AWS 배포 전에 Terraform state를 보관할 S3 버킷과 GitHub Actions의 임시 AWS 인증 기반을 마련한다. `preprod`와 `prod`의 state를 분리하고, PR에서 Terraform 형식·구성 검사와 환경별 plan을 검토할 수 있게 한다.

완료 기준은 bootstrap 코드와 AWS 적용·state 이전 검증, PR CI 통과, 사람의 PR 리뷰 및 merge다. GitHub 환경과 저장소 변수를 설정하기 전에는 AWS plan 작업이 건너뛰도록 설계했다.

## 작업 내용과 결정

- `infra/bootstrap`: S3 state 버킷에 공개 접근 차단, HTTPS 강제, SSE-S3 암호화, 버전 관리를 적용했다. `force_destroy=false`로 설정했다. GitHub OIDC provider와 `aws-fullstack-lab-plan` 역할을 만들고, 알림 이메일이 있을 때 월 $5 Budget을 생성한다.
- `infra/plan`: `preprod/terraform.tfstate`와 `prod/terraform.tfstate`를 별도 S3 key로 사용하며 계정 식별을 읽는 최소 Terraform 구성을 마련했다.
- `.github/workflows/terraform.yml`: PR에서 fmt·validate를 실행하고, GitHub 환경과 변수가 준비된 같은 저장소 PR에서만 OIDC plan을 실행한다. fork PR에는 AWS 역할을 제공하지 않는다.
- `README.md`, `AGENTS.md`, `docs/product.md`, `docs/architecture.md`, `docs/operations.md`, `infra/README.md`: 목표, 경계, 비용, 인증과 운영 순서를 정리했다.

GitHub OIDC 신뢰 정책에는 확인된 저장소 소유자·저장소의 immutable ID와 `preprod-plan`·`prod-plan` 환경을 사용했다. plan 역할은 환경별 state 읽기와 잠금 파일 작업만 허용한다. 앱 서비스 리소스와 배포용 apply 역할은 이 Task의 범위에 포함하지 않았다.

## AWS 적용과 재구성 절차

2026-09-23에 계정 `065768154598`의 `ap-northeast-2`에서 bootstrap을 적용했다. Terraform 결과는 **9개 생성, 변경·삭제 0개**다. 버킷 이름은 `aws-ecs-fullstack-app`, 원격 state key는 `bootstrap/terraform.tfstate`다. Budget은 월 $5에 실제 사용 80%와 예상 사용 100% 이메일 알림을 둔다. 적용 당시 인증 주체는 계정 root였다.

동일한 구성을 새 계정에 재현할 때는 [운영 가이드의 선행 준비와 1. Bootstrap](../operations.md#1-bootstrap)을 순서대로 따른다.

1. Terraform 1.14+, AWS CLI v2, S3·IAM·Budgets 변경 권한을 준비하고 AWS 계정·리전·무료 플랜 상태를 확인한다. `aws login` 세션이 만료되면 다시 로그인한다.
2. `infra/bootstrap/terraform.tfvars.example`을 복사해 전역에서 유일한 버킷 이름, 알림 이메일, 현재 GitHub 저장소 immutable subject를 입력한다. `.tfvars`와 자격 증명은 커밋하지 않는다.
3. `terraform init`, `fmt -check`, `validate`, `plan`으로 생성 범위를 검토한 뒤 `apply`한다. `aws login` 프로필을 S3 backend가 직접 읽지 못하면 운영 가이드의 `credential_process` 프로필을 사용한다.
4. `backend.s3.tf.example`을 복사하고 로컬 state를 `bootstrap/terraform.tfstate`로 이전한다. 원격 객체·S3 버전 관리·공개 접근 차단을 확인한 다음 `terraform plan -detailed-exitcode`가 0인지 확인한다. 이전이 검증될 때까지 로컬 state를 안전하게 보관한다.

이 계정에서는 원격 state의 객체 버전 ID 생성과 버킷 버전 관리·공개 접근 차단을 확인했다. 이전 후 plan은 `No changes`였다. 로컬 state 백업과 `.tfvars`는 Git에서 제외하고 파일 권한을 소유자 전용으로 설정했다.

## 검증과 운영 영향

- 로컬 Terraform fmt·validate 통과. AWS bootstrap plan은 9개 생성만 포함했고 적용 후 원격 state 기반 plan은 변경 없음이었다.
- PR #1의 앱 CI와 Terraform validate CI는 통과했다. AWS plan 작업은 GitHub 환경·저장소 변수가 아직 없어 건너뛰었다.
- S3 저장량과 요청은 사용량에 따라 비용 또는 Free plan 크레딧을 사용할 수 있다. 알림 전용 Budget은 무료지만 지출을 중단하지 않는다. 버킷과 state를 종료하려면 state를 먼저 백업하고 의존하는 환경의 state 사용을 중지한 뒤 [운영 가이드의 복구 절차](../operations.md#롤백과-복구)에 따라 정리한다.
- 향후 운영은 root 대신 권한을 제한한 IAM 주체로 전환한다. 현재 PR이 merge되기 전이므로 Task 완료 기록은 아직 없다.

## 남은 사항과 다음 Task

다음 Task 후보는 **GitHub PR plan 환경 구성**이다. `preprod-plan`·`prod-plan` 환경 보호 규칙을 확인하고, bootstrap output에 맞는 `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_ACCOUNT_ID`, `AWS_REGION` 저장소 변수를 설정한다. 이후 같은 저장소 PR에서 두 환경의 plan이 실행되는지 검증한다. PR #1 merge가 확인되면 Task 002 문서를 만들고 이 Task의 완료일·merge commit을 기록한다.
