# AWS ECS 인프라

이 저장소는 preprod·prod의 AWS 인프라와 운영 절차를 관리한다. Next.js 앱, 앱 CI와 앱 배포는 [앱 저장소](https://github.com/ban-dal/aws-ecs-fullstack-web)에 있다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `infra/bootstrap` | 계정·IAM 루트: state 버킷, 인프라·앱 GitHub OIDC 역할, 공통 ECS 역할, Budget, 운영 역할, ECR 스캔 |
| `infra/environments/<환경>` | 환경별 VPC, ECR, ECS, preprod VPN, prod ALB·HTTPS |
| `infra/modules` | AWS 서비스별 Terraform 모듈. 규칙은 [인프라 문서](infra/README.md) 참조 |
| `.github/workflows/terraform.yml` | PR에서 fmt·validate와 환경별 plan, main 인프라 변경에서 정적 검사 |
| `.github/workflows/apply-foundation.yml` | main에서 수동으로 기반 인프라 적용. prod는 승인 필수 |
| `scripts/` | bootstrap 적용, 정책 검사, GitHub 설정 검사, 서비스 운영 |

## 배포 경계

인프라 PR은 Terraform plan을 검토한 뒤 main에 merge한다. main push에는 인프라 정적 검사만 자동 실행된다. 기반 리소스는 `Apply service foundation`을 수동 실행해 적용하고, bootstrap IAM은 운영자가 `scripts/bootstrap.sh`로 적용한다.

앱 저장소의 `preprod` push는 preprod에 자동 배포하고, `main` push는 prod 배포 workflow를 자동 시작한다. prod 역할은 `main` 전용 `prod-deploy` 환경 승인 후에만 수임한다. 앱 역할은 각 환경의 ECR 저장소·ECS 서비스에만 접근한다. Terraform은 신규 생성용 태스크 정의를 관리하며 활성 ECS 서비스 revision은 앱 배포 workflow가 관리한다.

## GitHub 설정

인프라 저장소 Actions는 장기 AWS 키 없이 OIDC 역할을 사용한다.

| 종류 | 이름 | 값 |
| --- | --- | --- |
| Secret | `AWS_ACCOUNT_ID` | bootstrap output `aws_account_id` |
| Secret | `TF_STATE_BUCKET` | bootstrap output `state_bucket` |
| Secret | `CLIENT_VPN_SERVER_CERTIFICATE_ARN` | `scripts/preprod-client-vpn.sh prepare` 출력 |
| Variable | `AWS_REGION` | `ap-northeast-2` |

계정 ID와 state 버킷은 공개 Actions 로그에서 가리도록 secret으로 둔다. 환경 보호 규칙과 변수의 기대값은 [`scripts/check-github-settings.sh`](scripts/check-github-settings.sh)가 기준이다. 앱 저장소는 자체 `AWS_ACCOUNT_ID` secret과 main 전용 `prod-deploy` 승인 환경을 사용한다. 앱 리전은 workflow에 지정한다.

## 적용 상태 확인

- **bootstrap:** main의 bootstrap 코드와 해당 PR 적용 댓글.
- **서비스 기반:** [GitHub Deployments](https://github.com/ban-dal/aws-ecs-fullstack-app/deployments)의 `*-apply` 환경.
- **앱:** [앱 저장소 Deployments](https://github.com/ban-dal/aws-ecs-fullstack-web/deployments)와 ECS 서비스 active revision.

## 문서

- [아키텍처](docs/architecture.md)
- [운영·비용·복구](docs/operations.md)
- [앱 제품·디자인](https://github.com/ban-dal/aws-ecs-fullstack-web/tree/main/docs)
