# AWS 풀스택 실험실

Next.js 앱과 AWS 인프라를 한 저장소에서 관리하는 프로젝트다. Terraform bootstrap과 GitHub 환경별 PR plan을 구성했다. Task 003에서 서비스 기반 네트워크와 ECR 코드를 준비했고, Task 004에서 수동 승인 적용 경로를 구성했다. Task 005에서 IAM 역할과 `preprod` 서비스 기반을 AWS에 적용했다. 앱 배포와 `prod` 기반 적용은 아직 진행하지 않았다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `apps/web` | Next.js 앱과 `/api/health` |
| `infra/bootstrap` | state S3 버킷, GitHub OIDC plan 역할, 선택형 비용 Budget |
| `infra/plan` | 환경별 원격 state·계정 확인·서비스 기반 모듈을 연결하는 PR plan 루트 |
| `infra/live` | VPC·서브넷·라우팅·보안 그룹·비공개 ECR 모듈 |
| `.github/workflows/ci.yml` | PR과 main의 앱 타입 검사·빌드 |
| `.github/workflows/terraform.yml` | PR Terraform fmt·validate, 설정 후 환경별 plan |
| `.github/workflows/apply-foundation.yml` | main에서 수동 실행하는 환경별 기반 인프라 plan·승인·apply |
| `docs/` | 제품, 디자인, 아키텍처, 운영 기준 |

## 로컬 실행

Node.js 22 이상과 pnpm 11.27.0이 필요하다.

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm dev
```

앱은 `http://localhost:3000`, 상태 확인은 `http://localhost:3000/api/health`에서 볼 수 있다. `pnpm typecheck`와 `pnpm build`로 검사한다. Docker 이미지는 저장소 루트에서 `docker build -f apps/web/Dockerfile -t aws-fullstack-web .`로 만든다.

## 다음 단계

1. [Task 005](docs/tasks/005-preprod-foundation-apply.md)의 적용 결과와 비용·재구성 기록을 검토한다.
2. `preprod` 결과를 기준으로 `prod` 적용을 별도로 결정한다.
3. ECS/EC2, ALB, ACM, Route 53, S3, Lambda를 비용 선택지와 함께 추가한다. 공개 앱은 기본적으로 끈다.

## 문서

- [제품 목표와 범위](docs/product.md)
- [화면 및 사용 경험](docs/design.md)
- [아키텍처와 기술 선택](docs/architecture.md)
- [초기 설정, 배포, 비용 및 장애 대응](docs/operations.md)
- [PR별 Task 기록과 재구성 이력](docs/tasks/README.md)

## 비용과 현재 상태

2026년 9월 기준 새 AWS Free plan은 크레딧과 기간 제한이 있다. bootstrap과 `preprod`의 S3 state 저장량·요청, 이후 ECR 이미지 저장·전송은 사용량에 따라 과금될 수 있다. `preprod` VPC·서브넷·보안 그룹·빈 ECR은 적용했다. ALB, Route 53 호스팅 영역·도메인, 퍼블릭 IPv4, NAT Gateway, EC2는 생성하지 않았다. 정확한 금액은 계정 생성일, 리전, 사용량에 따라 확인해야 한다.
