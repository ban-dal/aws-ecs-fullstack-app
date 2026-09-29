# AWS ECS 인프라

이 저장소는 preprod·prod의 AWS 인프라와 운영 절차를 관리한다. Next.js 앱, 앱 CI와 앱 배포는 [앱 저장소](https://github.com/ban-dal/aws-ecs-fullstack-web)에 있다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `infra/bootstrap` | 계정·IAM 루트: state 버킷, 앱 GitHub OIDC 역할, 공통 ECS 역할, Budget, 운영 역할, ECR 스캔 |
| `infra/environments/<환경>` | 환경별 VPC, ECR, ECS, preprod VPN, prod ALB·HTTPS |
| `infra/modules` | AWS 서비스별 Terraform 모듈. 규칙은 [인프라 문서](infra/README.md) 참조 |
| `.github/workflows/terraform.yml` | PR과 main 인프라 변경에서 fmt·validate·스크립트 정적 검사. AWS 자격 없음 |
| `scripts/` | 루트별 plan·apply와 정책 검사, GitHub 설정 검사, 서비스 운영 |

## 배포 경계

인프라 PR은 운영자가 로컬에서 만든 plan 요약을 검토한 뒤 main에 merge한다. CI는 정적 검사만 한다. merge 후 운영자가 MFA 운영 역할로 `scripts/infra.sh`를 실행해 bootstrap·preprod·prod를 적용한다. GitHub에 계정 관리자 권한을 주지 않도록 인프라 저장소에는 AWS 역할을 두지 않는다.

앱 저장소의 `preprod`·`main` push는 각각 preprod·prod 이미지를 빌드해 ECS에 자동 배포한다. prod 역할은 `main` 전용 `prod-deploy` 환경을 통해서만 수임한다. 앱 역할은 각 환경의 ECR 저장소·ECS 서비스에만 접근한다. Terraform은 신규 생성용 태스크 정의를 관리하며 활성 ECS 서비스 revision은 앱 배포 workflow가 관리한다.

## GitHub 설정

인프라 저장소 Actions는 AWS 자격을 쓰지 않으므로 secret·변수·배포 환경이 없다. 앱 저장소는 자체 `AWS_ACCOUNT_ID` secret과 main 전용 `prod-deploy` 환경을 사용하고, 앱 리전은 workflow에 지정한다. 기대값은 [`scripts/check-github-settings.sh`](scripts/check-github-settings.sh)가 기준이다.

## 적용 상태 확인

- **인프라 루트:** main의 코드와 해당 PR의 적용 댓글. 현재 상태는 `scripts/infra.sh <루트> plan`이 변경 없음인지로 확인한다.
- **앱:** [앱 저장소 Deployments](https://github.com/ban-dal/aws-ecs-fullstack-web/deployments)와 ECS 서비스 active revision.

## 문서

- [아키텍처](docs/architecture.md)
- [운영·비용·복구](docs/operations.md)
- [앱 제품·디자인](https://github.com/ban-dal/aws-ecs-fullstack-web/tree/main/docs)
