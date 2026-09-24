# 운영 가이드

지금 유효한 절차만 둔다. 적용 상태는 [README](../README.md#적용-상태-확인), 설정의 이유는 해당 코드와 스크립트의 주석, 실행 결과는 해당 PR 댓글을 본다.

## 누가 무엇을 적용하나

| 대상 | 적용 주체 | 경로 |
| --- | --- | --- |
| 서비스 기반 (`infra/environments/<환경>`: VPC·보안 그룹·ECR 저장소) | GitHub 환경별 apply 역할 | [4절](#4-서비스-기반-적용)의 `Apply service foundation` |
| bootstrap 중 state 버킷, OIDC 제공자, GitHub 역할의 정책·신뢰 정책 | 운영 역할 `aws-fullstack-lab-bootstrap-operator` | [2절](#2-bootstrap-변경-적용)의 `scripts/bootstrap.sh` |
| bootstrap 중 운영 사용자·역할, Budget, GitHub 역할 boundary 정책, ECR 레지스트리 스캔 설정 | 계정 root 세션 | [2절](#2-bootstrap-변경-적용)의 `scripts/bootstrap.sh` |
| 콘솔 비밀번호, MFA 장치 | 사용자 본인 | IAM 콘솔 |

PR CI는 apply하지 않는다. merge만으로 배포가 시작되지 않는다.

## 1. 로컬 인증

장기 액세스 키를 만들지 않는다. `aws configure export-credentials`의 출력이나 MFA 코드를 로그·문서·대화에 붙여 넣지 않는다. 프로필은 개인 기기의 `~/.aws/config`에만 둔다. `AWS_PROFILE`은 Terraform을 실행하는 셸에 설정해야 한다.

### 운영 역할 (일상)

AWS CLI v2.32.0 이상이 필요하다. `aws login`은 브라우저에 남은 세션을 고를 수 있으므로 첫 호출 주체가 `user/aws-fullstack-lab-operator`인지 확인한다. AWS CLI/API는 패스키 MFA를 지원하지 않으므로 `mfa_serial`에는 인증 앱(TOTP) 장치 ARN을 쓴다.

```bash
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-login
aws login --profile aws-fullstack-operator-login
aws sts get-caller-identity --profile aws-fullstack-operator-login

aws configure set credential_process 'aws configure export-credentials --profile aws-fullstack-operator-login --format process' --profile aws-fullstack-operator-source
aws configure set region ap-northeast-2 --profile aws-fullstack-operator-source
aws configure set role_arn arn:aws:iam::<account-id>:role/aws-fullstack-lab-bootstrap-operator --profile aws-fullstack-operator
aws configure set source_profile aws-fullstack-operator-source --profile aws-fullstack-operator
aws configure set mfa_serial arn:aws:iam::<account-id>:mfa/aws-fullstack-lab-operator --profile aws-fullstack-operator
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

PR의 환경별 plan은 `infra/environments/<환경>`만 실행하므로 bootstrap 변경을 보여 주지 않는다. bootstrap을 바꾸는 PR은 작성 중에 `scripts/bootstrap.sh plan`을 실행해 변경 요약과 정책 테스트 결과를 PR 본문에 적는다.

PR merge 후:

1. `main`을 최신으로 받고 [누가 무엇을 적용하나](#누가-무엇을-적용하나)에 따라 프로필을 고른다.
2. `scripts/bootstrap.sh plan`을 실행한다. 저장 plan을 만들고, 생성·수정·삭제 요약을 출력하고, [정책 테스트](../infra/bootstrap/tests/iam.test.mjs)를 실행한다. 요약이 PR에 적은 범위와 다르거나 테스트가 실패하면 중단한다.
3. `scripts/bootstrap.sh apply`로 같은 저장 plan을 적용한다. `main`이 `origin/main`과 같고, plan을 만든 commit과 같고, 커밋하지 않은 변경이 없을 때만 실행된다. 적용 후 plan이 변경 없음인지 확인하고 저장 plan을 지운다.
4. GitHub 변수 등 후속 설정이 PR에 적혀 있으면 곧바로 진행하고 `scripts/check-github-settings.sh`로 확인한다.
5. 스크립트 출력(호출 주체, commit, 변경 요약, 사후 plan)을 해당 PR에 댓글로 남긴다.

`terraform.tfvars`(계정 ID, 버킷 이름, 알림 이메일 등)는 커밋하지 않는다. 저장 plan은 사용자 임시 디렉터리에만 둔다.

## 3. GitHub 설정

넣어야 할 secret·변수와 값의 출처는 [README의 GitHub 설정](../README.md#github-설정)에 있다. `scripts/check-github-settings.sh`가 기대하는 설정의 기준이며, 어긋난 항목을 `FAIL`로 출력하고 설정은 바꾸지 않는다.

```bash
scripts/check-github-settings.sh
```

`FAIL` 항목은 저장소의 Settings → Secrets and variables, Settings → Environments 또는 `gh` 명령으로 맞춘다.

## 4. 서비스 기반 적용

PR에서는 두 환경의 plan 요약과 바뀐 인프라 파일이 PR 댓글 하나에 올라오고, push할 때마다 갱신된다. 적용 workflow가 막는 변경이 있으면 그 댓글에 표시된다.

1. GitHub Actions에서 `Apply service foundation`을 `main`의 환경 하나로 실행한다.
2. `*-plan`을 승인한다. 실행 화면의 요약에서 변경과 검사 결과를 확인한다.
3. `*-apply`를 승인한다. 적용 작업은 plan을 다시 만들어, 승인한 plan과 변경 내용이 같을 때만 적용한다. 그사이 인프라가 바뀌었으면 적용하지 않고 실패하므로 workflow를 다시 실행한다. 서비스 기반 모듈 안의 생성·수정만 허용하고 삭제·교체는 막는다([`scripts/tfplan.sh`](../scripts/tfplan.sh)).
4. 적용 기록은 GitHub Deployments의 `*-apply` 환경에 자동으로 남는다. 계기가 된 PR에 실행 링크를 댓글로 남긴다.

`prod`는 `preprod` 결과와 비용을 검토한 뒤 따로 결정한다. 서비스 기반 plan은 PR이나 이 workflow의 plan 단계에서 확인한다. 운영 역할에는 EC2 읽기 권한이 없어 로컬 `infra/environments/<환경>` plan은 지원하지 않는다.

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

5. [README의 GitHub 설정](../README.md#github-설정)대로 GitHub 환경, secret, 변수를 bootstrap output 값으로 채우고 [3절](#3-github-설정)의 스크립트로 확인한다.
6. IAM 콘솔에서 `aws-fullstack-lab-operator`의 콘솔 접근을 켠다. 사용자는 초기 비밀번호를 바꾸고, 필요하면 콘솔용 패스키와 함께 이름이 `aws-fullstack-lab-operator`인 인증 앱 MFA를 등록한다. [1절](#운영-역할-일상)의 프로필로 `scripts/bootstrap.sh plan`이 변경 없음과 테스트 통과를 보이면 root 세션을 로그아웃한다.
7. [4절](#4-서비스-기반-적용)로 `preprod`부터 적용한다.

## 6. 비용 관리

- 새 AWS Free plan은 최대 6개월 또는 크레딧 소진 시 끝난다(2026년 9월 기준). Billing의 Free Tier 85% 알림과 크레딧 잔여량을 확인한다.
- Budget([`modules/budgets`](../infra/modules/budgets/main.tf))은 이메일로 알리기만 하고 지출을 멈추지 않는다.
- IAM, VPC, Internet Gateway 자체는 무료다. S3 state 저장·요청과 ECR 이미지 저장·전송은 사용량에 따라 과금된다. state 버킷의 이전 버전은 lifecycle 규칙으로 만료된다.
- 퍼블릭 IPv4, EC2, ALB, Route 53 호스팅 영역은 과금 대상이다. 추가하는 PR에서 서울 리전 요금으로 비용을 계산하고, 공개 앱은 기본적으로 끈다. NAT Gateway는 쓰지 않는다.

## 7. 종료·롤백·복구

- 서비스 기반 종료: ECS·ALB 등 종속 리소스를 먼저 없앤다. ECR은 `force_delete=false`이므로 이미지를 비운 뒤 삭제한다. 현재 workflow에는 destroy 경로가 없으므로 환경별 `terraform plan -destroy`를 검토하는 별도 절차를 PR로 만든다.
- bootstrap 롤백: 되돌리는 PR을 merge한 뒤 [2절](#2-bootstrap-변경-적용)로 적용하고, 바뀐 GitHub 변수를 되돌린다.
- Terraform 오류: 마지막 성공 state의 S3 버전을 확인하고 state를 손으로 고치지 않는다. `terraform plan`으로 선언과 실제의 차이를 먼저 본다.
- state 버킷: 삭제 전에 `bootstrap`, `preprod`, `prod` state를 백업하고 OIDC 역할 사용을 멈춘다. 버킷은 `force_destroy=false`다.
- 운영 역할이나 MFA가 고장 나면 root로 복구하고, 원인과 조치를 관련 PR 댓글 또는 이슈에 남긴다.

## 외부 참고

- [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/)
- [AWS Budgets 요금](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/), [ECR 요금](https://aws.amazon.com/ecr/pricing/), [VPC 요금](https://aws.amazon.com/vpc/pricing/), [ALB 요금](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [GitHub OIDC와 AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [GitHub 환경](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [AWS CLI 역할·MFA 설정](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-role.html), [AWS CLI 임시 로그인](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html), [IAM 가상 MFA](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_mfa_enable_virtual.html)
