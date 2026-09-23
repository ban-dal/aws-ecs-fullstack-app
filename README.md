# AWS 풀스택 실험실

Next.js 앱과 AWS 인프라를 한 저장소에서 관리하기 위한 초기 프로젝트다. 이번 초기 커밋에는 실행 가능한 앱, pnpm 워크스페이스, CI, 기획·디자인·아키텍처·운영 문서를 담았다. Terraform과 AWS 배포는 다음 PR에서 구현한다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `apps/web` | Next.js 앱과 `/api/health` |
| `infra/README.md` | 후속 Terraform 구현 안내 |
| `.github/workflows/ci.yml` | PR과 main의 앱 타입 검사·빌드 |
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

1. Terraform으로 state 저장소와 GitHub OIDC 역할을 준비한다.
2. VPC, 서브넷, 보안 그룹, ECR, ECS/EC2, ALB, ACM, Route 53, S3, Lambda를 비용 선택지와 함께 구현한다.
3. PR에서 `terraform fmt`, `validate`, 환경별 `plan`을 실행하고, 리뷰·merge 후 preprod `apply`, 수동 승인 후 prod `apply`를 연결한다.

## 문서

- [제품 목표와 범위](docs/product.md)
- [화면 및 사용 경험](docs/design.md)
- [아키텍처와 기술 선택](docs/architecture.md)
- [초기 설정, 배포, 비용 및 장애 대응](docs/operations.md)

## 비용과 현재 상태

2026년 9월 기준 새 AWS Free plan은 크레딧과 기간 제한이 있다. ALB, Route 53 호스팅 영역·도메인, 퍼블릭 IPv4, NAT Gateway 등은 사용량 또는 시간에 따라 과금될 수 있다. 아직 AWS 리소스는 만들지 않았다. 정확한 금액은 계정 생성일, 리전, 사용량에 따라 확인해야 한다.
