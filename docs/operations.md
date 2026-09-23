# 운영 가이드

> 이 문서는 후속 Terraform 구현을 위한 운영 계획이다. 현재 AWS 계정 연결, 배포 워크플로, 실제 리소스는 없다. 아래 명령은 Terraform 구현 후에 사용할 수 있다.

## 선행 준비

Node.js 22+, pnpm 11.27.0, Terraform 1.14+, AWS CLI, Docker와 권한 있는 AWS 계정이 필요하다. AWS 계정에 새 Free plan 혜택이 적용되는지 Billing에서 확인한다. Route 53 hosted zone은 이 Terraform이 생성하지 않는다. 도메인 등록과 NS 위임을 먼저 완료한다.

## 1. Bootstrap

후속 PR에서 `infra/bootstrap`을 만든 뒤 변수 예제를 개인 `.tfvars`로 복사한다. state S3 버킷에는 전역 유일한 이름을 넣는다. GitHub OIDC subject는 실제 토큰 값을 확인한다. GitHub 2026년 7월 이후 생성 저장소는 `repo:owner@OWNER_ID/repo@REPO_ID` 같은 immutable subject를 사용할 수 있다.

Bootstrap state의 저장·복구 경로를 구현 PR에서 정해야 한다. state와 비밀 값은 커밋하지 않는다. 같은 AWS 계정에 GitHub OIDC provider가 이미 있으면 새로 만들기 전 Terraform import로 관리 대상을 맞춘다.

## 2. GitHub 설정

예정 변수: `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN`, `AWS_REGION`, `HOSTED_ZONE_ID`, `PREPROD_DOMAIN_NAME`, `PROD_DOMAIN_NAME`, `ENABLE_PUBLIC_APP`. 공개 서비스는 초기 `false`로 둔다. hosted zone과 ACM 인증서의 도메인·리전이 맞아야 한다.

Terraform 배포를 구현할 때 GitHub 환경 `preprod-plan`, `prod-plan`, `preprod`, `prod`를 생성한다. 배포 환경에는 `main` branch 제한을 두고 `prod`에는 필수 승인자를 설정한다. GitHub Actions OIDC 신뢰 정책과 환경 보호는 한 쌍이다.

## 3. 배포와 확인

현재 PR과 main에서는 앱 타입 검사와 빌드만 실행한다. 목표 흐름은 PR에서 Terraform fmt·validate·두 환경 plan → 리뷰·merge → preprod apply → 수동 승인 후 prod apply다.

배포 후 도메인과 `/api/health`, ECS 서비스 이벤트, CloudWatch 로그, ALB target health, ACM 검증 CNAME을 확인한다.

## 비용 관리

2026년 9월 기준 새 AWS Free plan은 최대 6개월 또는 크레딧 소진 시 끝난다. 무료 플랜 대상 서비스와 혜택은 계정 생성 시점에 따라 다르다. ALB 시간·LCU, Route 53 hosted zone과 도메인, 퍼블릭 IPv4, EC2/EBS, S3, ECR·로그 저장량은 요금 또는 크레딧을 사용할 수 있다. 두 환경에서 공개 앱을 켜면 EC2와 ALB도 각각 생성된다. 계획에는 NAT Gateway를 넣지 않는다. Billing에서 예산·알림을 설정하고 배포 전 AWS Pricing Calculator로 리전별 비용을 계산한다. 리소스 종료 절차는 Terraform 구현과 함께 확정한다.

## 롤백과 복구

- 앱 롤백: 이전 정상 이미지 digest로 `image_uri`를 지정해 해당 환경 Terraform apply를 실행한다. 파이프라인 재실행은 최신 커밋 이미지를 다시 만들므로 이전 코드 롤백에는 revert PR을 권장한다.
- Terraform 오류: 마지막 성공 state와 S3 version을 확인하고, 임의로 state를 편집하지 않는다. `terraform plan`으로 실제 리소스와 선언 차이를 확인한다.
- 인증서 대기: Route 53 NS 위임과 ACM DNS 검증 레코드가 전파되었는지 확인한다.
- 서비스 비정상: ECS 이벤트, EC2 등록 상태, 로그 그룹, target group의 `/api/health`를 확인한다.

## 외부 참고

- [AWS Free Tier](https://aws.amazon.com/free/)
- [AWS Free Tier FAQ](https://aws.amazon.com/free/free-tier-faqs/)
- [ALB 요금](https://aws.amazon.com/elasticloadbalancing/pricing/)
- [NAT Gateway 요금](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html)
- [GitHub OIDC와 AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
