# 운영 가이드

Terraform bootstrap은 2026-09-23에 적용했고 state를 S3로 이전했다. GitHub PR plan 환경과 저장소 변수를 설정했으며, PR #2에서 두 환경의 실제 plan을 검증했다. 아래 bootstrap 명령은 새 계정에서 재현할 때 참고하며, 현재 계정에서는 원격 state를 연결한 뒤 plan으로 상태를 확인한다.

## 선행 준비

로컬 검증에는 Terraform 1.14+가 필요하다. AWS 적용에는 S3·IAM·Budgets 변경 권한이 있는 AWS 자격 증명과 전역에서 유일한 버킷 이름이 필요하다. AWS 계정의 Free plan 기간과 크레딧을 Billing에서 확인한다. 도메인·Route 53은 이번 작업에 필요하지 않다.

### 최초 bootstrap용 로컬 CLI 인증

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

이 절은 최초 bootstrap에 사용한 기존 프로필을 재구성하기 위한 기록이다. Task 006 적용과 MFA 검증 후에는 [6절](#6-비루트-운영-주체)의 비루트 프로필을 사용한다. SSO를 쓰는 계정에서는 `aws login` 대신 `aws configure sso --profile aws-fullstack-bootstrap`과 `aws sso login --profile aws-fullstack-bootstrap`을 실행한다. Terraform의 S3 backend가 `aws login` 프로필을 직접 읽지 못하는 경우 `credential_process` 프로필로 AWS CLI의 임시 자격 증명을 공유한다. `AWS_PROFILE`은 Terraform 명령을 실행하는 셸에 설정해야 하며 Codex 데스크톱 앱은 별도 실행 환경이므로 터미널의 `export`를 자동으로 상속하지 않는다. Codex 샌드박스에서 로그인 캐시 접근이 차단되면 AWS 명령에 샌드박스 밖 실행 권한이 필요하다. 인증 파일을 저장소로 복사하지 않는다. 세션이 만료되면 `aws login --profile aws-fullstack-bootstrap`을 다시 실행한다. [AWS CLI 로그인 안내](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)와 [S3 backend 인증](https://developer.hashicorp.com/terraform/language/backend/s3)을 참고한다.

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

2026-09-23에 `preprod-plan`·`prod-plan` 환경에 `ban-dal` 필수 수동 승인자를 설정하고 자기 환경 승인(`prevent_self_review=false`)을 허용했다. 이후 bootstrap output과 대조한 네 저장소 변수를 등록하고 읽어 확인했다. [PR #2 실행](https://github.com/ban-dal/aws-ecs-fullstack-app/actions/runs/35823513637)에서 두 환경 작업을 각각 승인했고, OIDC 인증·S3 backend 초기화·예상 계정 확인·plan 성공을 확인했다. 두 plan은 `plan_identity` 출력값 추가만 표시했으며 실제 인프라 변경은 없었다.

GitHub Actions는 장기 AWS 키를 저장하지 않는다. plan 역할은 환경별 state 읽기와 잠금 파일 작업, 서비스 기반 VPC·ECR refresh용 읽기 권한을 갖는다. Task 005에서 해당 읽기 정책을 AWS에 적용했다. state 객체 쓰기 권한은 plan 역할에 없다.

## 3. 배포와 확인

현재 PR은 앱 타입 검사·빌드와 Terraform fmt·validate를 실행한다. 같은 저장소 PR에서는 `preprod`·`prod` 원격 state plan을 실행한다. Task 003의 `infra/plan`은 계정 식별 후 `infra/live` 서비스 기반 모듈을 plan한다. `terraform plan`은 AWS 리소스를 만들지 않는다. Task 004의 보호된 apply workflow는 merge된 `main`에서만 수동 실행할 수 있다.

향후 앱 배포 후에는 도메인과 `/api/health`, ECS 서비스 이벤트, CloudWatch 로그, ALB target health, ACM 검증 CNAME을 확인한다.

## 4. 서비스 기반 네트워크와 ECR

[Task 003](tasks/003-service-foundation.md)은 각 환경에 VPC, 두 AZ의 공개·비공개 서브넷, Internet Gateway와 공개 라우트, ALB·ECS 호스트 보안 그룹, 비공개 ECR을 선언한다. NAT, EC2, ALB, 퍼블릭 IPv4는 포함하지 않는다. `preprod`와 `prod`의 state key는 기존 `preprod/terraform.tfstate`, `prod/terraform.tfstate`를 그대로 쓴다.

AWS 콘솔 또는 `aws ec2 describe-availability-zones --region ap-northeast-2`로 두 AZ가 계정에 사용 가능한지 확인한다. 기본값은 `ap-northeast-2a`와 `ap-northeast-2c`다. 다른 AZ를 써야 하면 두 환경의 plan에서 `availability_zones` 입력을 같은 순서로 지정한다. 적용 후 AZ 순서를 바꾸면 서브넷 교체가 발생할 수 있다.

[PR #3 Terraform 실행](https://github.com/ban-dal/aws-ecs-fullstack-app/actions/runs/35824838577)에서 두 환경 각각 17개 생성, 변경·삭제 0개를 확인했다. `preprod`는 `10.60.0.0/16`, `prod`는 `10.61.0.0/16`이며 두 환경 모두 퍼블릭 IP 자동 할당이 꺼져 있다. 로컬에서 plan할 때는 `infra/bootstrap`의 원격 state를 먼저 초기화하고 아래처럼 **환경을 바꿀 때마다 `-reconfigure`**를 사용한다. 이는 두 환경 state를 하나로 이전하지 않기 위한 설정이다.

```bash
export TF_STATE_BUCKET="$(terraform -chdir=infra/bootstrap output -raw state_bucket)"
export TF_VAR_expected_account_id="$(terraform -chdir=infra/bootstrap output -raw aws_account_id)"
terraform -chdir=infra/plan init -reconfigure -input=false \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=preprod/terraform.tfstate" \
  -backend-config="region=ap-northeast-2"
terraform -chdir=infra/plan plan -input=false -var="environment=preprod"
```

Task 003은 코드와 PR plan까지만 진행했다. Task 005에서 plan 역할의 VPC·ECR 읽기 정책과 환경별 적용 역할을 포함한 `infra/bootstrap` 변경을 승인받아 적용했다. 보호된 `preprod` apply도 완료해 결과를 확인했다. `prod`는 별도 결정과 환경 승인으로 적용한다. GitHub PR CI에서는 apply하지 않는다.

2026-09-23 [preprod 적용 실행 35853428651](https://github.com/ban-dal/aws-ecs-fullstack-app/actions/runs/35853428651)은 plan·apply 단계에서 모두 계정 `065768154598`을 확인하고, 기반 리소스 **17개 생성·변경 0개·삭제 0개**로 성공했다. VPC `vpc-0fb4b83dae7ac8bc2`의 네 서브넷은 `ap-northeast-2a`와 `ap-northeast-2c`에 분산되며 퍼블릭 IP 자동 할당은 모두 꺼져 있다. 공개 라우트만 Internet Gateway로 향한다. ECR `aws-fullstack-lab-preprod-web`은 빈 저장소로 생성됐다. 사후 preprod plan은 변경 없음이다. prod state의 plan은 여전히 17개 생성만 표시하며 prod는 미적용 상태다.

VPC와 Internet Gateway 자체에는 추가 요금이 없지만, ECR에 이미지를 넣으면 저장량·데이터 전송량에 따라 비용이 생긴다. 새 고객의 ECR 프라이빗 저장소에는 월 500 MB 저장 공간의 무료 이용 범위가 안내되어 있으나 실제 계정 자격과 초과 사용량을 확인해야 한다. 퍼블릭 IPv4는 생성하지 않았으며 나중에 할당하면 시간당 요금이 발생한다. [VPC FAQ](https://aws.amazon.com/vpc/faqs/), [Internet Gateway 안내](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Internet_Gateway.html), [ECR 요금](https://aws.amazon.com/ecr/pricing/), [VPC 요금](https://aws.amazon.com/vpc/pricing/)을 참고한다.

종료할 때는 후속 ECS·ALB 등 종속 리소스를 먼저 제거한다. ECR 저장소는 `force_delete=false`이므로 이미지를 비운 뒤 삭제한다. 환경별 state로 `terraform plan -destroy`를 검토하고 승인된 destroy 절차로 제거한다. bootstrap의 state 버킷과 OIDC 역할은 별도로 유지한다.

## 5. 보호된 서비스 기반 적용

[Task 004](tasks/004-protected-foundation-apply.md)는 `preprod-apply`, `prod-apply` GitHub 환경과 환경별 OIDC 역할, [수동 적용 workflow](../.github/workflows/apply-foundation.yml)를 준비한다. 환경은 `main` 브랜치만 허용하고 `ban-dal` 수동 승인을 요구한다. 사용자가 선택한 1인 운영 정책으로 자기 승인은 허용하지만 독립 검토자는 없다. 기존 `preprod-plan`, `prod-plan` 승인과 적용 승인은 서로 다른 작업이다.

2026-09-23에 두 적용 환경을 설정하고 API로 다시 확인했다. `prevent_self_review=false`, 필수 승인자 `ban-dal`, 배포 가능한 브랜치 패턴은 `main` 하나다. 각 환경의 `AWS_APPLY_ROLE_ARN`은 `arn:aws:iam::065768154598:role/aws-fullstack-lab-<environment>-apply` 형식으로 등록했다. Task 005에서 역할을 AWS에 생성하고 두 환경 변수와 실제 역할 ARN이 일치하는지 확인했다. 다른 계정에서 재구성할 때는 계정 ID와 GitHub 사용자 ID를 새 값으로 바꾼다. [GitHub 환경 API](https://docs.github.com/en/rest/deployments/environments)와 [브랜치 정책 API](https://docs.github.com/en/rest/deployments/branch-policies)를 참고한다.

workflow는 `main`에서 수동으로 `preprod` 또는 `prod` 하나를 선택해 실행한다. 먼저 해당 `*-plan` 환경을 승인하고 로그의 변경을 확인한다. 이어 `*-apply` 환경을 승인하면 새 plan을 만들어 검사한 뒤 그 plan을 적용한다. 현재 안전장치는 `module.service_foundation` 안에서 최대 17개 **신규 생성**만 허용한다. 변경·교체·삭제나 다른 모듈의 변경은 실패한다. plan 파일과 JSON은 runner 임시 디렉터리에서만 사용하며 artifact로 올리지 않는다. merge만으로 배포가 시작되지 않는다.

### 최초 IAM 권한 준비

새 계정에서 적용 역할을 처음 생성할 때는 아직 workflow를 사용할 수 없다. Task 004 PR을 검토·merge한 뒤, 기존 관리자 자격 증명으로 bootstrap state에 한 번 적용하는 예외가 필요하다. 이 예외는 서비스 리소스를 만들지 않는다. 계정과 `main` commit을 확인하고, `terraform plan`에서 `foundation_plan_read` 정책 1개와 환경별 적용 역할·정책 각 2개, 총 **5개 생성·변경 0개·삭제 0개**인지 재확인한다. 결과가 다르면 진행하지 않는다.

```bash
test "$(git branch --show-current)" = "main"
export AWS_PROFILE=aws-fullstack-terraform
aws sts get-caller-identity
if [ ! -f infra/bootstrap/backend.s3.tf ]; then
  cp infra/bootstrap/backend.s3.tf.example infra/bootstrap/backend.s3.tf
fi
terraform -chdir=infra/bootstrap init -reconfigure -input=false \
  -backend-config="bucket=aws-ecs-fullstack-app" \
  -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=ap-northeast-2"
TF_PLAN_DIR="$(mktemp -d)"
trap 'rm -rf "$TF_PLAN_DIR"' EXIT
terraform -chdir=infra/bootstrap plan -input=false \
  -var-file=terraform.tfvars -out="$TF_PLAN_DIR/bootstrap.tfplan"
terraform -chdir=infra/bootstrap show -no-color "$TF_PLAN_DIR/bootstrap.tfplan"
# plan과 계정 확인 후 별도 승인 시에만 실행
terraform -chdir=infra/bootstrap apply -input=false "$TF_PLAN_DIR/bootstrap.tfplan"
terraform -chdir=infra/bootstrap output foundation_apply_role_arns
```

`backend.s3.tf`, `terraform.tfvars`, plan 파일과 자격 증명을 커밋하지 않는다. 실제 적용 뒤에는 실행자, 날짜, commit, plan·apply 결과와 두 IAM 역할 ARN을 이 문서 또는 다음 Task에 기록한다. 기존 관리자 자격 증명을 계속 배포에 사용하지 않는다. [Terraform 저장 plan](https://developer.hashicorp.com/terraform/tutorials/cli/plan)에는 민감한 데이터가 들어갈 수 있으므로 임시 디렉터리에서만 사용한다.

#### 2026-09-23 최초 IAM 적용 기록

- 실행자: Codex가 사용자의 승인 후 `aws-fullstack-terraform` 프로필로 실행했다. AWS 호출 주체는 계정 `065768154598`의 root 임시 세션이었다.
- 코드: PR #4 merge commit `3d4ec05fb97b7ad361fe608e93122686c727ea9a`의 `main`. 원격 state: `s3://aws-ecs-fullstack-app/bootstrap/terraform.tfstate`.
- 저장 plan: 환경별 적용 역할 2개, 역할 정책 2개, plan 읽기 정책 1개 생성. 변경·삭제 0개. `terraform apply`도 5개 생성, 변경·삭제 0개였다.
- 사후 `terraform plan -detailed-exitcode`는 종료 코드 0으로 변경 없음이었다. `foundation_apply_role_arns`의 두 ARN을 GitHub 적용 환경 변수와 대조했다. 저장 plan은 확인 후 임시 디렉터리에서 삭제했다.
- 이 단계에서 VPC·ECR 등 서비스 기반은 생성하지 않았다. [Task 005](tasks/005-preprod-foundation-apply.md)에 이어지는 `preprod` 실행을 기록한다.

### 환경별 서비스 기반 적용

bootstrap 적용 후 `foundation_apply_role_arns`의 `preprod`·`prod` 값을 각 GitHub 적용 환경의 `AWS_APPLY_ROLE_ARN` 변수와 대조한다. `TF_STATE_BUCKET`, `AWS_ACCOUNT_ID`, `AWS_REGION`, `AWS_PLAN_ROLE_ARN`은 기존 저장소 변수를 사용한다. 장기 AWS 키는 등록하지 않는다.

1. GitHub Actions에서 `Apply service foundation`을 `main`의 `preprod`로 수동 실행한다. `preprod-plan` 승인 후 plan 결과와 예상 계정을 확인하고, `preprod-apply`를 승인한다.
2. 적용 로그, `preprod/terraform.tfstate`, VPC·서브넷·보안 그룹·ECR 존재를 확인한다. 이 workflow는 공개 앱이나 EC2·ALB를 만들지 않는다.
3. 비용과 preprod 결과를 검토한 뒤에만 `prod`를 별도 실행한다. `prod-plan`, `prod-apply`도 각각 승인한다.

2026-09-23에 1·2단계를 실행했다. 두 환경 승인 후 같은 저장 plan의 17개 신규 생성 검사가 통과했고 apply는 17개 생성으로 끝났다. S3 preprod state 객체의 버전과 AES256 암호화, VPC·라우팅·보안 그룹·ECR 설정을 AWS API로 확인했다. VPC에는 NAT Gateway·EC2·ALB가 없다. 실행 세부 내용은 [Task 005](tasks/005-preprod-foundation-apply.md)에 기록했다. 3단계 prod 적용은 아직 진행하지 않았다.

두 환경은 서로 다른 state key와 ECR 이름·VPC CIDR을 사용한다. 적용 역할의 S3 state 쓰기 권한도 환경별 key로 나뉜다. 다만 EC2 네트워크 생성·삭제 API 권한은 서울 리전으로 제한할 뿐 환경별 리소스 ID까지 묶지 못했다. 한 AWS 계정을 공유하는 한 실수에 대한 완전한 환경 격리는 아니다. 이 workflow에는 destroy 경로가 없으며 종료 시에는 별도 검토된 절차를 만든다.

## 6. 비루트 운영 주체

[Task 006](tasks/006-nonroot-operator.md)은 사람의 콘솔·로컬 CLI 운영을 계정 root에서 옮긴다. 이 프로젝트는 학습용 `preprod`·`prod`를 한 계정에서 논리적으로 분리한다. AWS Organizations를 만들거나 계정을 가입시키지 않는다. 현재 Free plan 계정이 Organizations에 가입하면 크레딧이 즉시 만료되고 유료 플랜으로 전환될 수 있으므로 [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/)를 확인한다.

`aws-fullstack-lab-operator` IAM 사용자는 콘솔 로그인과 `aws login`용 관리형 정책, 운영 역할 수임, 자신의 비밀번호·MFA 등록 권한만 가진다. `aws-fullstack-lab-bootstrap-operator` 역할은 해당 사용자와 MFA가 확인된 세션만 신뢰한다. 역할은 이 프로젝트의 state 버킷, GitHub OIDC 제공자와 기존 GitHub 역할을 관리하고, 자기 역할·사용자·Budget 설정은 읽는다. 자기 역할 정책과 Budget 변경 권한은 없다. GitHub Actions의 plan·apply OIDC 경로는 그대로 유지한다.

### PR merge 후 최초 적용

1. 계정 root에 MFA가 활성화됐는지 확인한다. 이는 계정 소유자가 자신의 기기로 직접 등록하며 MFA 코드와 복구 자료를 저장소나 대화에 올리지 않는다. [AWS root MFA 안내](https://docs.aws.amazon.com/IAM/latest/UserGuide/root-user-best-practices.html)를 따른다.
2. PR merge 뒤 `main`에서 기존 관리자 프로필로 계정과 원격 bootstrap state를 확인한다. `terraform -chdir=infra/bootstrap plan -out=<임시 경로>`의 **IAM 사용자 1개, 역할 1개, 사용자 정책 1개, 사용자 관리형 정책 연결 1개, 역할 정책 1개 생성·기존 리소스 변경/삭제 0개**를 확인한 뒤 저장 plan을 적용한다. 사용자 콘솔 비밀번호·MFA 장치와 장기 액세스 키는 Terraform에서 만들지 않는다. 저장 plan은 임시 디렉터리에 두고 적용 후 삭제한다.
3. IAM 콘솔에서 새 사용자의 콘솔 접근을 활성화한다. 초기 비밀번호는 사용자만 안전하게 받아 변경하고, 자신의 MFA 장치를 이름 `aws-fullstack-lab-operator`로 등록한다. 콘솔에 사용자로 로그인해 `aws-fullstack-lab-bootstrap-operator` 역할로 전환되는지 확인한다. [IAM 사용자 MFA 등록 안내](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_virtual.html)를 참고한다.
4. 비루트 CLI 프로필을 구성하고 호출 주체와 변경 없는 bootstrap plan을 확인한다. 마지막 검증 전에는 root 경로를 제거하지 않는다.

### 비루트 CLI 프로필

AWS CLI v2.32.0 이상에서 IAM 사용자로 로그인한다. 브라우저에 root 세션이 남아 있으면 `aws login`이 그 세션을 선택할 수 있으므로 첫 `get-caller-identity` 결과의 ARN이 반드시 `user/aws-fullstack-lab-operator`인지 확인한다. 다르면 로그아웃한 뒤 IAM 사용자로 다시 로그인한다. MFA 장치 ARN은 해당 사용자 IAM 보안 자격 증명 화면에서 확인한다.

```bash
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-login
aws login --profile aws-fullstack-operator-login
aws sts get-caller-identity --profile aws-fullstack-operator-login

aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-operator-login --format process' --profile aws-fullstack-operator-source
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-source
aws configure set role_arn arn:aws:iam::065768154598:role/aws-fullstack-lab-bootstrap-operator --profile aws-fullstack-operator
aws configure set source_profile aws-fullstack-operator-source --profile aws-fullstack-operator
aws configure set mfa_serial '<사용자 MFA 장치 ARN>' --profile aws-fullstack-operator
aws configure set region ap-northeast-2 --profile aws-fullstack-operator

export AWS_PROFILE=aws-fullstack-operator
aws sts get-caller-identity
terraform -chdir=infra/bootstrap init -reconfigure -input=false \
  -backend-config='bucket=aws-ecs-fullstack-app' \
  -backend-config='key=bootstrap/terraform.tfstate' \
  -backend-config='region=ap-northeast-2'
terraform -chdir=infra/bootstrap plan -detailed-exitcode -input=false \
  -var-file=terraform.tfvars
```

`get-caller-identity`의 ARN은 `assumed-role/aws-fullstack-lab-bootstrap-operator/`로 시작해야 하고, 변경 없는 plan은 종료 코드 0이어야 한다. 현재 역할은 프로젝트 bootstrap 관리용이다. 서비스 기반 적용은 계속 보호된 GitHub workflow에서 실행한다. 장기 액세스 키를 발급하거나 `aws configure export-credentials`의 출력을 로그·문서에 붙여 넣지 않는다. 로컬 프로필은 개인 기기의 `~/.aws/config`에만 저장한다. 이 단계가 성공하면 일상 작업에서 root 세션을 로그아웃한다. 운영 역할이나 MFA가 고장 난 경우에만 계정 root의 복구 절차를 사용하고 원인을 기록한다.

AWS IAM Identity Center의 독립 계정용 account instance는 AWS 계정 접근용 permission set을 지원하지 않아 이 단일 계정의 사람 로그인 경로로 사용하지 않는다. [AWS Identity Center 인스턴스 비교](https://docs.aws.amazon.com/singlesignon/latest/userguide/identity-center-instances.html), [AWS CLI 역할·MFA 설정](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html), [AWS CLI 임시 로그인](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)을 참고한다.

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
