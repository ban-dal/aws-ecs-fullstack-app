# 운영 가이드

Terraform bootstrap은 2026-09-23에 적용했고 state를 S3로 이전했다. GitHub PR plan 환경과 저장소 변수도 설정했으며, 실제 PR plan 결과는 검증 중이다. 아래 bootstrap 명령은 새 계정에서 재현할 때 참고하며, 현재 계정에서는 원격 state를 연결한 뒤 plan으로 상태를 확인한다.

## 선행 준비

로컬 검증에는 Terraform 1.14+가 필요하다. AWS 적용에는 S3·IAM·Budgets 변경 권한이 있는 AWS 자격 증명과 전역에서 유일한 버킷 이름이 필요하다. AWS 계정의 Free plan 기간과 크레딧을 Billing에서 확인한다. 도메인·Route 53은 이번 작업에 필요하지 않다.

### 로컬 CLI 인증

Terraform과 AWS CLI v2를 설치한 뒤 프로젝트 전용 프로필의 리전을 설정한다. IAM 사용자 또는 콘솔 로그인 계정은 `aws login`으로 임시 자격 증명을 받는다. IAM Identity Center 사용자라면 `aws configure sso`와 `aws sso login`을 사용한다. 액세스 키와 비밀 키는 저장소나 대화에 기록하지 않는다.

```bash
terraform version
aws --version
aws configure set region ap-northeast-2 --profile aws-fullstack-bootstrap
aws login --profile aws-fullstack-bootstrap
aws sts get-caller-identity --profile aws-fullstack-bootstrap
aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-bootstrap --format process' --profile aws-fullstack-terraform
aws configure set region ap-northeast-2 --profile aws-fullstack-terraform
export AWS_PROFILE=aws-fullstack-terraform
aws sts get-caller-identity
```

SSO를 쓰는 계정에서는 `aws login` 대신 `aws configure sso --profile aws-fullstack-bootstrap`과 `aws sso login --profile aws-fullstack-bootstrap`을 실행한다. Terraform의 S3 backend가 `aws login` 프로필을 직접 읽지 못하는 경우 `credential_process` 프로필로 AWS CLI의 임시 자격 증명을 공유한다. `AWS_PROFILE`은 Terraform 명령을 실행하는 셸에 설정해야 하며 Codex 데스크톱 앱은 별도 실행 환경이므로 터미널의 `export`를 자동으로 상속하지 않는다. Codex 샌드박스에서 로그인 캐시 접근이 차단되면 AWS 명령에 샌드박스 밖 실행 권한이 필요하다. 인증 파일을 저장소로 복사하지 않는다. 세션이 만료되면 `aws login --profile aws-fullstack-bootstrap`을 다시 실행한다. [AWS CLI 로그인 안내](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)와 [S3 backend 인증](https://developer.hashicorp.com/terraform/language/backend/s3)을 참고한다.

## 1. Bootstrap

`infra/bootstrap/terraform.tfvars.example`을 `infra/bootstrap/terraform.tfvars`로 복사한다. 버킷 이름과 알림 이메일을 입력한다. 이 저장소의 GitHub OIDC 기본 subject는 `repo:ban-dal@46153202/aws-ecs-fullstack-app@1382568125`로 확인했다. 저장소가 이전·재생성되면 GitHub 설정을 다시 확인한다. 이메일이 `null`이면 Budget이 생성되지 않는다. 비용 Budget은 크레딧을 제외한 사용 비용을 기준으로 월간 80% 실제 사용과 100% 예상 사용을 알린다.

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap fmt -check
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan -var-file=terraform.tfvars
terraform -chdir=infra/bootstrap apply -var-file=terraform.tfvars
```

첫 apply는 로컬 state를 만든다. 이후 `infra/bootstrap/backend.s3.tf.example`을 `backend.s3.tf`로 복사하고, 같은 버킷의 `bootstrap/terraform.tfstate`로 이전한다. 이전과 S3 버전 확인이 끝날 때까지 로컬 state를 안전하게 보관한다. `backend.s3.tf`, `.tfvars`, state는 Git에서 제외한다. 기존 계정에서는 새로 apply하지 말고 먼저 원격 backend를 연결한다.

```bash
cp infra/bootstrap/backend.s3.tf.example infra/bootstrap/backend.s3.tf
terraform -chdir=infra/bootstrap init -migrate-state \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=ap-northeast-2"
terraform -chdir=infra/bootstrap output
```

계정에 `token.actions.githubusercontent.com` OIDC provider가 이미 있으면 중복 생성 전에 해당 리소스를 import한다. bootstrap state 버킷은 `force_destroy=false`이므로 실수로 state 전체를 지우는 동작을 막는다.

### 2026-09-23 실행 기록

이 작업의 목표, 선택 이유와 재구성 체크리스트는 [Task 001](tasks/001-terraform-foundation.md)에 기록했다.

- 계정 `065768154598`, 리전 `ap-northeast-2`에 S3 state 버킷 `aws-ecs-fullstack-app`, GitHub OIDC provider와 plan 역할, 월 $5 비용 Budget을 생성했다. Terraform 결과는 9개 생성, 변경·삭제 0개였다.
- 로컬 state를 `s3://aws-ecs-fullstack-app/bootstrap/terraform.tfstate`로 이전했다. 객체 버전 ID가 생성되고 버킷 버전 관리·공개 접근 차단이 활성화된 것을 확인했다. 이전 후 `terraform plan -detailed-exitcode`는 변경 없음(종료 코드 0)이었다.
- 당시 AWS 인증 주체는 계정 root였다. 후속 운영에는 권한을 제한한 IAM 주체를 사용한다. GitHub 환경 보호 규칙과 저장소 변수는 2단계에서 설정해야 한다.

## 2. GitHub 설정

GitHub 환경 `preprod-plan`, `prod-plan`을 만들고 승인 규칙을 설정한다. 저장소 변수 `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_ACCOUNT_ID`에는 bootstrap output 값을, `AWS_REGION`에는 버킷 리전을 넣는다. 앞의 세 변수 중 하나라도 없으면 PR의 AWS plan 작업은 건너뛴다. fork PR도 AWS 자격 증명을 받지 않는다. 이 저장소에서 온 PR은 환경 승인 후에만 plan 역할을 사용하도록 환경 보호를 설정한다. plan은 호출한 AWS 계정 ID가 bootstrap 계정과 같은지도 확인한다.

1인 저장소에서는 PR 작성자가 자신의 PR에 Approve할 수 없는 것과 GitHub 환경 작업을 승인하는 것은 다른 규칙이다. 환경의 자기 승인 방지(`prevent_self_review`)를 켜면 작업을 시작한 계정 외에 승인자가 필요하다. 이를 끄면 같은 계정이 환경 작업을 승인할 수 있으나 독립 검토는 이루어지지 않는다. 승인 정책을 먼저 결정하고 환경 보호를 설정한 다음 저장소 변수를 등록한다. 결정과 실제 설정은 [Task 002](tasks/002-github-pr-plan-setup.md)에 기록한다.

2026-09-23에 `preprod-plan`·`prod-plan` 환경에 `ban-dal` 필수 수동 승인자를 설정하고 자기 환경 승인(`prevent_self_review=false`)을 허용했다. 이후 bootstrap output과 대조한 네 저장소 변수를 등록하고 읽어 확인했다. PR #2의 두 plan 작업을 각각 승인해 실제 결과를 검증해야 한다.

현재 OIDC 역할은 환경별 `preprod/terraform.tfstate`, `prod/terraform.tfstate` 읽기와 잠금 파일 작업에만 접근한다. GitHub Actions는 장기 AWS 키를 저장하지 않는다. 향후 서비스 리소스를 추가할 때 provider의 필요한 읽기 권한을 검토해 role policy를 늘린다.

## 3. 배포와 확인

현재 PR은 앱 타입 검사·빌드와 Terraform fmt·validate를 실행한다. bootstrap을 적용하고 GitHub 변수를 등록하면 같은 저장소의 PR에 `preprod`·`prod` 원격 state plan이 추가된다. `infra/plan`은 계정 식별만 읽으며 AWS 리소스를 생성하지 않는다. PR 리뷰·merge 후의 apply는 후속 서비스 작업에서 만든다.

향후 앱 배포 후에는 도메인과 `/api/health`, ECS 서비스 이벤트, CloudWatch 로그, ALB target health, ACM 검증 CNAME을 확인한다.

## 비용 관리

2026년 9월 기준 새 AWS Free plan은 최대 6개월 또는 크레딧 소진 시 끝난다. 이번 bootstrap의 S3 저장량·요청에는 요금 또는 크레딧 사용이 생길 수 있다. 알림만 있는 AWS Budget은 무료지만 예산 알림은 지출을 자동 중단하지 않는다. Billing의 Free Tier 85% 알림과 크레딧 잔여량을 함께 확인한다. 후속 ALB·Route 53·EC2 등은 리전별 비용을 별도 계산하고 공개 앱은 기본적으로 끈다. NAT Gateway는 계획에 넣지 않는다.

## 롤백과 복구

- Terraform 오류: 마지막 성공 state와 S3 version을 확인하고, 임의로 state를 편집하지 않는다. `terraform plan`으로 실제 리소스와 선언 차이를 확인한다.
- bootstrap 재구성: 버킷 삭제 전에 `bootstrap`, `preprod`, `prod` state를 백업한다. OIDC 역할이 사용 중인지 확인하고, state 이전 없이 버킷을 없애지 않는다.
- 앱 롤백·인증서·ECS 장애 절차는 해당 리소스를 구현할 때 추가한다.

## 외부 참고

- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/)
- [ALB 요금](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [NAT Gateway 요금](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- [GitHub OIDC와 AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [AWS Budgets 요금](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/)
