# 운영 가이드

지금 유효한 절차만 둔다. 무엇이 적용됐는지는 [README의 현재 상태](../README.md#현재-상태), 왜 이렇게 하는지는 [결정 기록](decisions/README.md), 언제 어떻게 실행했는지는 해당 PR과 PR 댓글을 본다.

## 누가 무엇을 적용하나

| 대상 | 적용 주체 | 경로 |
| --- | --- | --- |
| 서비스 기반 (`infra/plan`: VPC·서브넷·보안 그룹·ECR) | GitHub 환경별 apply 역할 | [4절](#4-서비스-기반-적용)의 `Apply service foundation` |
| bootstrap 중 state 버킷, OIDC 제공자, GitHub 역할의 정책·신뢰 정책 | 운영 역할 `aws-fullstack-lab-bootstrap-operator` | [2절](#2-bootstrap-변경-적용)의 로컬 저장 plan |
| bootstrap 중 운영 사용자·역할, Budget, GitHub 역할 boundary 정책 | 계정 root 세션 | [2절](#2-bootstrap-변경-적용)의 로컬 저장 plan |
| 콘솔 비밀번호, MFA 장치 | 사용자 본인 | IAM 콘솔 |

PR CI는 apply하지 않는다. merge만으로 배포가 시작되지 않는다.

## 1. 로컬 인증

장기 액세스 키를 만들지 않는다. `aws configure export-credentials`의 출력이나 MFA 코드를 로그·문서·대화에 붙여 넣지 않는다. 프로필은 개인 기기의 `~/.aws/config`에만 둔다. `AWS_PROFILE`은 Terraform을 실행하는 셸에 설정해야 한다.

### 운영 역할 (일상)

AWS CLI v2.32.0 이상이 필요하다. `aws login`은 브라우저에 남은 세션을 고를 수 있으므로 첫 호출 주체가 `user/aws-fullstack-lab-operator`인지 확인한다. `mfa_serial`에는 패스키가 아닌 인증 앱(TOTP) 장치 ARN을 쓴다([0004](decisions/0004-human-operator-access.md)).

```bash
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-login
aws login --profile aws-fullstack-operator-login
aws sts get-caller-identity --profile aws-fullstack-operator-login

aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-operator-login --format process' --profile aws-fullstack-operator-source
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-source
aws configure set role_arn arn:aws:iam::065768154598:role/aws-fullstack-lab-bootstrap-operator --profile aws-fullstack-operator
aws configure set source_profile aws-fullstack-operator-source --profile aws-fullstack-operator
aws configure set mfa_serial arn:aws:iam::065768154598:mfa/aws-fullstack-lab-operator --profile aws-fullstack-operator
aws configure set region ap-northeast-2 --profile aws-fullstack-operator
aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-operator --format process' --profile aws-fullstack-operator-terraform
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-terraform
```

작업할 때마다 먼저 역할을 수임한다. 첫 명령에서 TOTP 코드를 입력하면 AWS CLI가 역할 세션을 최대 1시간 캐시하고, Terraform은 그 세션을 `aws-fullstack-operator-terraform` 프로필로 받는다. Terraform에 `aws-fullstack-operator`를 직접 쓰면 `AssumeRoleTokenProvider session option not set` 오류가 난다.

```bash
aws sts get-caller-identity --profile aws-fullstack-operator
export AWS_PROFILE=aws-fullstack-operator-terraform
aws sts get-caller-identity
```

두 ARN 모두 `assumed-role/aws-fullstack-lab-bootstrap-operator/`로 시작해야 한다.

### root (예외)

운영 역할 권한 밖의 bootstrap 변경과 계정 복구에만 쓴다. root에는 MFA가 켜져 있어야 한다. 작업이 끝나면 브라우저와 CLI 세션을 로그아웃한다.

```bash
aws configure set region ap-northeast-2 --profile aws-fullstack-bootstrap
aws login --profile aws-fullstack-bootstrap
aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-bootstrap --format process' --profile aws-fullstack-terraform
aws configure set region ap-northeast-2 --profile aws-fullstack-terraform
export AWS_PROFILE=aws-fullstack-terraform
aws sts get-caller-identity
```

## 2. bootstrap 변경 적용

bootstrap 변경은 PR에서 plan 범위(생성·수정·삭제 개수와 대상)를 먼저 밝힌다. PR의 환경별 plan은 `infra/plan`만 실행하므로 bootstrap 변경은 보여 주지 않는다.

1. PR merge 후 `main`을 최신으로 받는다. [누가 무엇을 적용하나](#누가-무엇을-적용하나)에 따라 프로필을 고르고 계정을 확인한다.
2. 저장 plan을 임시 디렉터리에 만들고, PR에 적은 범위와 같은지 확인한다. 다르면 중단한다.
3. 같은 저장 plan을 적용하고, 사후 plan이 변경 없음(종료 코드 0)인지 확인한다.
4. GitHub 변수 등 후속 설정이 PR에 적혀 있으면 곧바로 진행한다.
5. 결과(실행 주체, commit, plan·apply 개수, 사후 plan, 후속 설정)를 해당 PR에 댓글로 남긴다.

```bash
test "$(git branch --show-current)" = "main"
aws sts get-caller-identity
terraform -chdir=infra/bootstrap init -reconfigure -input=false \
  -backend-config='bucket=aws-ecs-fullstack-app' \
  -backend-config='key=bootstrap/terraform.tfstate' \
  -backend-config='region=ap-northeast-2'
TF_PLAN_DIR="$(mktemp -d)"
trap 'rm -rf "$TF_PLAN_DIR"' EXIT
terraform -chdir=infra/bootstrap plan -input=false \
  -var-file=terraform.tfvars -out="$TF_PLAN_DIR/bootstrap.tfplan"
terraform -chdir=infra/bootstrap show -no-color "$TF_PLAN_DIR/bootstrap.tfplan"
# 범위 확인 후에만 실행
terraform -chdir=infra/bootstrap apply -input=false "$TF_PLAN_DIR/bootstrap.tfplan"
terraform -chdir=infra/bootstrap plan -detailed-exitcode -input=false -var-file=terraform.tfvars
```

저장 plan에는 민감한 값이 들어갈 수 있으므로 임시 디렉터리에서만 쓴다. `terraform.tfvars`(계정 ID, 버킷 이름, 알림 이메일 등)는 커밋하지 않는다.

GitHub 역할의 boundary([0005](decisions/0005-github-role-boundary.md))는 서비스 단위로 권한을 제한한다. 새 AWS 서비스를 쓰는 PR은 boundary 확장을 함께 넣고 root로 적용한다.

## 3. GitHub 설정

| 환경 | 보호 규칙 | 변수 |
| --- | --- | --- |
| `preprod-plan`, `prod-plan` | `ban-dal` 수동 승인, 자기 승인 허용 | `AWS_PLAN_ROLE_ARN` = `plan_role_arns` output의 해당 값 |
| `preprod-apply`, `prod-apply` | `ban-dal` 수동 승인, 자기 승인 허용, `main` 브랜치만 | `AWS_APPLY_ROLE_ARN` = `foundation_apply_role_arns` output의 해당 값 |

저장소 변수는 `TF_STATE_BUCKET`, `AWS_ACCOUNT_ID`, `AWS_REGION`이다. `TF_STATE_BUCKET`이나 `AWS_ACCOUNT_ID`가 없으면 PR의 AWS plan은 건너뛰고, 환경 변수 `AWS_PLAN_ROLE_ARN`이 없으면 역할 확인 단계에서 실패한다. fork PR은 AWS 자격을 받지 않는다. 환경 보호 규칙을 변수보다 먼저 만든다([0002](decisions/0002-github-oidc-approvals.md)).

## 4. 서비스 기반 적용

1. GitHub Actions에서 `Apply service foundation`을 `main`의 환경 하나로 실행한다.
2. `*-plan`을 승인하고 로그의 변경과 AWS 계정을 확인한다.
3. `*-apply`를 승인한다. 적용 작업은 plan을 다시 만들고, `module.service_foundation` 안의 신규 생성만 있을 때 그 plan을 적용한다. 수정·교체·삭제가 있으면 실패한다([0003](decisions/0003-protected-apply.md)).
4. 결과를 해당 PR 또는 관련 이슈에 댓글로 남긴다.

`prod`는 `preprod` 결과와 비용을 검토한 뒤 따로 결정한다. 서비스 기반 plan은 PR이나 이 workflow의 plan 단계에서 확인한다. 운영 역할에는 EC2 읽기 권한이 없어 로컬 `infra/plan` plan은 지원하지 않는다.

기본 AZ는 `ap-northeast-2a`, `ap-northeast-2c`다. 계정에서 쓸 수 없으면 두 환경의 `availability_zones`를 같은 순서로 지정한다. 적용 후 AZ 순서를 바꾸면 서브넷이 교체된다.

## 5. 새 계정 재구성

1. Terraform 1.14+, AWS CLI v2.32+를 준비한다. root MFA를 켜고 [1절](#root-예외)의 root 프로필을 만든다. Free plan 기간과 크레딧을 Billing에서 확인한다.
2. `infra/bootstrap/terraform.tfvars.example`을 `terraform.tfvars`로 복사해 계정 ID, 전역에서 유일한 버킷 이름, 알림 이메일, GitHub OIDC subject를 넣는다. 저장소가 이전·재생성되면 subject의 immutable ID를 다시 확인한다. 이메일이 `null`이면 Budget을 만들지 않는다.
3. state 버킷이 아직 없으므로 첫 apply는 Git에서 제외되는 local backend override로 한다. 계정에 GitHub OIDC 제공자가 이미 있으면 먼저 import한다.

   ```bash
   printf 'terraform {\n  backend "local" {}\n}\n' > infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init
   terraform -chdir=infra/bootstrap plan -var-file=terraform.tfvars
   terraform -chdir=infra/bootstrap apply -var-file=terraform.tfvars
   ```

4. override를 지우고 로컬 state를 S3로 옮긴다. 원격 객체와 버킷 버전 관리를 확인하고 사후 plan이 변경 없음일 때까지 로컬 state를 안전하게 보관한다.

   ```bash
   rm infra/bootstrap/backend_override.tf
   terraform -chdir=infra/bootstrap init -migrate-state \
     -backend-config="bucket=<state-bucket>" \
     -backend-config="key=bootstrap/terraform.tfstate" \
     -backend-config="region=ap-northeast-2"
   terraform -chdir=infra/bootstrap output
   ```

5. [3절](#3-github-설정)의 GitHub 환경과 변수를 output 값으로 설정한다. 다른 계정이면 계정 ID와 GitHub 사용자 ID를 새 값으로 바꾼다.
6. IAM 콘솔에서 `aws-fullstack-lab-operator`의 콘솔 접근을 켠다. 사용자는 초기 비밀번호를 바꾸고, 필요하면 콘솔용 패스키와 함께 이름이 `aws-fullstack-lab-operator`인 인증 앱 MFA를 등록한다. [1절](#운영-역할-일상)의 프로필로 bootstrap plan이 변경 없음인지 확인한 뒤 root 세션을 로그아웃한다.
7. [4절](#4-서비스-기반-적용)로 `preprod`부터 적용한다.

## 6. 비용 관리

- 새 AWS Free plan은 최대 6개월 또는 크레딧 소진 시 끝난다(2026년 9월 기준). Billing의 Free Tier 85% 알림과 크레딧 잔여량을 확인한다.
- Budget은 크레딧을 제외한 사용 비용 기준으로 월간 80% 실제 사용과 100% 예상 사용을 이메일로 알린다. 알림만 할 뿐 지출을 멈추지 않는다.
- IAM, VPC, Internet Gateway 자체는 무료다. S3 state 저장·요청과 ECR 이미지 저장·전송은 사용량에 따라 과금된다. state 버킷의 이전 버전은 90일 뒤 만료된다(최근 10개 유지).
- 퍼블릭 IPv4, EC2, ALB, Route 53 호스팅 영역은 과금 대상이다. 추가하는 PR에서 서울 리전 요금으로 비용을 계산하고, 공개 앱은 기본적으로 끈다. NAT Gateway는 쓰지 않는다.

## 7. 종료·롤백·복구

- 서비스 기반 종료: ECS·ALB 등 종속 리소스를 먼저 없앤다. ECR은 `force_delete=false`이므로 이미지를 비운 뒤 삭제한다. 현재 workflow에는 destroy 경로가 없으므로 환경별 `terraform plan -destroy`를 검토하는 별도 절차를 PR로 만든다.
- bootstrap 롤백: 이전 `main` commit의 구성으로 [2절](#2-bootstrap-변경-적용)의 저장 plan을 만들어 적용하고, 바뀐 GitHub 변수를 되돌린다.
- Terraform 오류: 마지막 성공 state의 S3 버전을 확인하고 state를 손으로 고치지 않는다. `terraform plan`으로 선언과 실제의 차이를 먼저 본다.
- state 버킷: 삭제 전에 `bootstrap`, `preprod`, `prod` state를 백업하고 OIDC 역할 사용을 멈춘다. 버킷은 `force_destroy=false`다.
- 운영 역할이나 MFA가 고장 나면 root로 복구하고, 원인과 조치를 관련 PR 또는 이슈에 남긴다.

## 외부 참고

- [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/)
- [AWS Budgets 요금](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/), [ECR 요금](https://aws.amazon.com/ecr/pricing/), [VPC 요금](https://aws.amazon.com/vpc/pricing/), [ALB 요금](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [GitHub OIDC와 AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [GitHub 환경](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [AWS CLI 역할·MFA 설정](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html), [AWS CLI 임시 로그인](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html), [IAM 가상 MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_virtual.html)
