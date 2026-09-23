# AWS 풀스택 실험실

Next.js 앱과 AWS 인프라를 한 저장소에서 관리하는 프로젝트다. AI가 기획·디자인·앱·인프라·운영 문서를 함께 유지하고, 사람이 PR로 리뷰한다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `apps/web` | Next.js 앱과 `/api/health` |
| `infra/bootstrap` | state S3 버킷, GitHub OIDC 역할과 boundary, 선택형 비용 Budget, 사람의 비루트 운영 역할 |
| `infra/plan` | 환경별 원격 state·계정 확인·서비스 기반 모듈을 연결하는 PR plan 루트 |
| `infra/live` | VPC·서브넷·라우팅·보안 그룹·비공개 ECR 모듈 |
| `.github/workflows/ci.yml` | PR과 main의 앱 타입 검사·빌드 |
| `.github/workflows/terraform.yml` | PR Terraform fmt·validate, 설정 후 환경별 plan |
| `.github/workflows/apply-foundation.yml` | main에서 수동 실행하는 환경별 기반 인프라 plan·승인·apply |
| `scripts/` | bootstrap plan·apply와 정책 테스트, GitHub 설정 확인 |
| `docs/` | 제품, 디자인, 아키텍처, 운영 절차 |

## 로컬 실행

Node.js 22 이상과 pnpm 11.27.0이 필요하다.

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm dev
```

앱은 `http://localhost:3000`, 상태 확인은 `http://localhost:3000/api/health`에서 볼 수 있다. `pnpm typecheck`와 `pnpm build`로 검사한다. Docker 이미지는 저장소 루트에서 `docker build -f apps/web/Dockerfile -t aws-fullstack-web .`로 만든다.

## 적용 상태 확인

상태를 문서에 따로 적지 않는다. 다음 두 곳이 기준이다.

- **bootstrap:** PR merge 직후 `scripts/bootstrap.sh`로 적용하므로 `main`의 `infra/bootstrap`이 곧 적용 상태다. 적용 결과는 해당 PR 댓글에 있다.
- **서비스 기반 (`preprod`, `prod`):** [GitHub Deployments](https://github.com/ban-dal/aws-ecs-fullstack-app/deployments)의 `*-apply` 환경에 마지막 적용 commit이 남는다. 기록이 없는 환경은 적용되지 않은 것이다.

## 다음 단계

1. 적용 workflow 개선: 신규 생성 전용 검사를 삭제·교체 차단 중심으로 바꾸고, 승인한 plan과 적용 plan을 묶는다. 액션 SHA 고정, `infra/plan`의 `allowed_account_ids`, PR plan 댓글을 추가한다.
2. 서비스 기반 보강: ECR `scan_on_push`, 보안 그룹 규칙 분리, provider `default_tags`.
3. `prod` 서비스 기반 적용.
4. 이미지 빌드·push, ECS on EC2, ALB·ACM·Route 53(공개 스위치 `enable_public_app` 기본 `false`), 배포 흐름과 종료 절차, S3·Lambda 예제를 비용 선택지와 함께 추가한다.

## 문서

- [제품 목표와 범위](docs/product.md)
- [화면 및 사용 경험](docs/design.md)
- [아키텍처와 기술 선택](docs/architecture.md)
- [운영 절차, 비용, 복구](docs/operations.md)

선택의 이유는 해당 코드나 스크립트 옆 주석에, 변경 이력은 PR과 PR 댓글에 있다. 이전의 PR별 Task 문서는 [`a3eb46f` 시점의 docs/tasks](https://github.com/ban-dal/aws-ecs-fullstack-app/tree/a3eb46f/docs/tasks)에 남아 있다.
