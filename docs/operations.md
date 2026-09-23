# 운영 가이드

Terraform bootstrap과 PR plan 코드가 준비되었다. 현재 AWS에는 적용하지 않았다. 아래 단계에서 AWS 리소스를 실제 생성하는 명령은 운영자가 계정과 비용을 확인한 후 실행한다.

## 선행 준비

로컬 검증에는 Terraform 1.14+가 필요하다. AWS 적용에는 S3·IAM·Budgets 변경 권한이 있는 AWS 자격 증명과 전역에서 유일한 버킷 이름이 필요하다. AWS 계정의 Free plan 기간과 크레딧을 Billing에서 확인한다. 도메인·Route 53은 이번 작업에 필요하지 않다.

## 1. Bootstrap

`infra/bootstrap/terraform.tfvars.example`을 `infra/bootstrap/terraform.tfvars`로 복사한다. 버킷 이름과 알림 이메일을 입력한다. 이 저장소의 GitHub OIDC 기본 subject는 `repo:ban-dal@46153202/aws-ecs-fullstack-app@1382568125`로 확인했다. 저장소가 이전·재생성되면 GitHub 설정을 다시 확인한다. 이메일이 `null`이면 Budget이 생성되지 않는다. 비용 Budget은 크레딧을 제외한 사용 비용을 기준으로 월간 80% 실제 사용과 100% 예상 사용을 알린다.

```bash
terraform -chdir=infra/bootstrap init
terraform -chdir=infra/bootstrap fmt -check
terraform -chdir=infra/bootstrap validate
terraform -chdir=infra/bootstrap plan -var-file=terraform.tfvars
terraform -chdir=infra/bootstrap apply -var-file=terraform.tfvars
```

첫 apply는 로컬 state를 만든다. 이후 `infra/bootstrap/backend.s3.tf.example`을 `backend.s3.tf`로 복사하고, 같은 버킷의 `bootstrap/terraform.tfstate`로 이전한다. 이전과 S3 버전 확인이 끝날 때까지 로컬 state를 안전하게 보관한다. `backend.s3.tf`와 `.tfvars`는 Git에서 제외한다.

```bash
cp infra/bootstrap/backend.s3.tf.example infra/bootstrap/backend.s3.tf
terraform -chdir=infra/bootstrap init -migrate-state \
  -backend-config="bucket=<state-bucket>" \
  -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=ap-northeast-2"
terraform -chdir=infra/bootstrap output
```

계정에 `token.actions.githubusercontent.com` OIDC provider가 이미 있으면 중복 생성 전에 해당 리소스를 import한다. bootstrap state 버킷은 `force_destroy=false`이므로 실수로 state 전체를 지우는 동작을 막는다.

## 2. GitHub 설정

GitHub 환경 `preprod-plan`, `prod-plan`을 만들고 승인 규칙을 설정한다. 저장소 변수 `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_ACCOUNT_ID`에는 bootstrap output 값을, `AWS_REGION`에는 버킷 리전을 넣는다. 앞의 세 변수 중 하나라도 없으면 PR의 AWS plan 작업은 건너뛴다. fork PR도 AWS 자격 증명을 받지 않는다. 이 저장소에서 온 PR은 환경 승인 후에만 plan 역할을 사용하도록 환경 보호를 설정한다. plan은 호출한 AWS 계정 ID가 bootstrap 계정과 같은지도 확인한다.

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
