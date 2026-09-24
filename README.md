# AWS 풀스택 실험실

Next.js 앱과 AWS 인프라를 한 저장소에서 관리하는 프로젝트다. AI가 기획·디자인·앱·인프라·운영 문서를 함께 유지하고, 사람이 PR로 리뷰한다.

## 구성

| 경로 | 용도 |
| --- | --- |
| `apps/web` | Next.js 앱과 `/api/health` |
| `infra/bootstrap` | 계정·IAM 루트: state 버킷, GitHub OIDC 역할 3개, 공통 ECS 역할 2개, 비용 Budget, 사람의 운영 역할, ECR 스캔 |
| `infra/environments/<환경>` | preprod·prod 서비스 루트: VPC, 보안 그룹, ECR 저장소와 preprod ECS 호스트·VPN |
| `infra/modules` | AWS 서비스 이름으로 나눈 모듈. 구조와 규칙은 [infra/README.md](infra/README.md) |
| `.github/workflows/ci.yml` | PR과 main의 앱 타입 검사·빌드 |
| `.github/workflows/terraform.yml` | PR Terraform fmt·validate, 설정 후 환경별 plan |
| `.github/workflows/apply-foundation.yml` | main에서 수동 실행하는 환경별 기반 인프라 plan·승인·apply |
| `.github/workflows/image.yml` | PR에서 arm64 이미지 빌드·health 확인, main에서 preprod·prod ECR에 같은 이미지 push |
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

## GitHub 설정

GitHub Actions는 AWS 장기 키 없이 OIDC 역할로 AWS에 접근한다. 그래서 AWS 액세스 키 secret은 두지 않는다. 필요한 값은 아래뿐이고, 모두 bootstrap을 적용한 뒤에 채운다.

| 종류 | 위치 | 이름 | 값 |
| --- | --- | --- | --- |
| Secret | 저장소 | `AWS_ACCOUNT_ID` | AWS 계정 ID(12자리). bootstrap output `aws_account_id` |
| Secret | 저장소 | `TF_STATE_BUCKET` | Terraform state 버킷 이름. bootstrap output `state_bucket` |
| Secret | 저장소 | `CLIENT_VPN_SERVER_CERTIFICATE_ARN` | `scripts/preprod-client-vpn.sh prepare`가 ACM에 가져온 preprod 서버 인증서 ARN |
| Variable | 저장소 | `AWS_REGION` | `ap-northeast-2` (state 버킷과 서비스 리소스의 리전) |

- 계정 ID와 버킷 이름을 변수가 아닌 secret으로 두는 이유는 공개 Actions 로그에서 가리기 위해서다. 같은 이름의 저장소 변수는 두지 않는다.
- plan·apply workflow는 이전 환경별 역할 변수가 있으면 전환 기간에만 사용한다. bootstrap 변경 적용 후 변수를 삭제하면 계정 ID secret과 공통 역할 이름으로 ARN을 만든다. image workflow는 공통 역할 이름을 사용한다.
- 환경 보호 규칙의 기대값은 [`scripts/check-github-settings.sh`](scripts/check-github-settings.sh)에 있다. 필수 승인은 `*-apply`에만 둔다.
- secret은 명령줄 인자로 넘기지 말고, 프롬프트에 붙여 넣거나 로컬 파일에서 읽어 넣는다. 셸 기록과 로그에 값을 남기지 않기 위해서다.

```bash
gh secret set AWS_ACCOUNT_ID --repo ban-dal/aws-ecs-fullstack-app
```

```bash
terraform -chdir=infra/bootstrap output -raw state_bucket | gh secret set TF_STATE_BUCKET --repo ban-dal/aws-ecs-fullstack-app
```

설정한 뒤 `scripts/check-github-settings.sh`로 위 표와 보호 규칙이 맞는지 확인한다. 이 스크립트가 기대값의 기준이며, 표와 다르면 스크립트를 기준으로 표를 고친다.

## 적용 상태 확인

상태를 문서에 따로 적지 않는다. 다음 두 곳이 기준이다.

- **bootstrap:** PR merge 직후 `scripts/bootstrap.sh`로 적용하므로 `main`의 `infra/bootstrap`이 곧 적용 상태다. 적용 결과는 해당 PR 댓글에 있다.
- **서비스 기반 (`preprod`, `prod`):** [GitHub Deployments](https://github.com/ban-dal/aws-ecs-fullstack-app/deployments)의 `*-apply` 환경에 마지막 적용 commit이 남는다. 기록이 없는 환경은 적용되지 않은 것이다.

## 다음 단계

preprod의 AWS Client VPN 인증서 접속을 검증한 뒤 기존 WireGuard를 제거한다. 이후 prod의 ALB·ACM·Route 53 공개 HTTPS와 이미지 승격 흐름을 추가한다. S3·Lambda 예제는 비용을 따로 검토한다.

## 문서

- [제품 목표와 범위](docs/product.md)
- [화면 및 사용 경험](docs/design.md)
- [아키텍처와 기술 선택](docs/architecture.md)
- [운영 절차, 비용, 복구](docs/operations.md)

선택의 이유는 해당 코드나 스크립트 옆 주석에, 변경 이력은 PR과 PR 댓글에 있다. 이전의 PR별 Task 문서는 [`a3eb46f` 시점의 docs/tasks](https://github.com/ban-dal/aws-ecs-fullstack-app/tree/a3eb46f/docs/tasks)에 남아 있다.
