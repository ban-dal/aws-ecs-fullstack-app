# 작업 지침

이 저장소는 AI가 기획, 디자인, 애플리케이션, 인프라와 운영 문서를 함께 유지하는 실험 프로젝트다. 변경 전 `README.md`와 변경 범위에 관련된 `docs/` 문서를 읽고, 코드와 문서가 어긋나면 같은 변경에서 함께 고친다.

## 기본 원칙

- 목표와 사용자 동작은 `docs/product.md`, 화면과 접근성 기준은 `docs/design.md`, 큰 구조는 `docs/architecture.md`, 운영 절차는 `docs/operations.md`를 기준으로 한다.
- Next.js 앱은 `apps/web`에 둔다. Terraform 기반은 `infra/bootstrap`, 환경별 PR plan은 `infra/plan`에 둔다. 후속 서비스 구성은 별도 live 디렉터리로 분리하고, 새 공유 패키지는 `packages/*`에 둔다.
- 현재는 pnpm workspaces만 사용한다. 빌드 단계가 복잡해질 때 Turbo를 추가한다.
- AWS 리소스나 비용을 늘리는 변경은 예상 비용, 종료 방법, 무료 플랜 영향, PR plan 결과를 설명한다. `enable_public_app`의 기본값은 `false`로 유지한다.
- Terraform state, `.tfvars`, 계정 비밀, AWS 자격 증명은 커밋하지 않는다. GitHub Actions는 OIDC를 사용한다.
- Terraform을 구현할 때 `preprod`와 `prod`는 서로 다른 S3 state key와 리소스 이름을 유지한다. 한 환경 변경이 다른 환경에 영향을 주는지 검토한다.
- 서비스 리소스의 `terraform apply`는 PR 리뷰와 merge 이후 GitHub 환경 보호 규칙을 통과해 실행한다. `infra/bootstrap`은 PR merge 후 `scripts/bootstrap.sh`로 로컬에서 적용하고, `apply` 전에 사용자 승인을 받는다. bootstrap 적용과 로컬 긴급 변경의 결과는 해당 PR 댓글에 남기고 코드에 반영한다.

## 테스트 및 검증

- 테스트를 새로 쓰거나 이름을 바꿀 때 `it`/`test` 제목은 한국어로 입력·상황과 예상 결과를 모두 포함한다. 예: `GET /api/health는 ok 상태를 반환한다`.
- 요청 범위의 실제 사용자 동작 또는 회귀 위험을 검증하는 테스트만 추가한다. 낮은 영향의 단순 속성·클래스 확인 테스트는 만들지 않는다.
- 앱 변경에는 `pnpm typecheck`, `pnpm build`를 실행한다. Terraform 변경에는 `terraform fmt -check`와 수정한 루트 모듈의 `terraform validate`를 실행한다.
- `infra/bootstrap` 변경에는 `scripts/bootstrap.sh plan`을 실행해 변경 요약과 정책 테스트 결과를 PR에 적는다. IAM 정책의 의도가 바뀌면 `infra/bootstrap/policy-tests/`의 테스트를 같은 PR에서 고친다.
- GitHub 환경이나 변수를 바꾼 뒤에는 `scripts/check-github-settings.sh`를 실행한다. 기대값이 바뀌면 스크립트를 같은 PR에서 고친다.
- 브라우저 동작은 필요한 경우 실제 브라우저에서 확인하고 검증 범위를 명시한다.

## 사실의 원천

같은 사실을 여러 파일에 쓰지 않는다. 사실마다 아래의 원천 한 곳만 고치고, 문서는 원천을 링크한다. 날짜별 실행 기록이나 번호순 결정 기록은 두지 않는다.

| 정보 | 원천 |
| --- | --- |
| 무엇이 선언돼 있나 | Terraform·workflow·스크립트 코드 |
| 왜 그렇게 했나 (보안·비용 트레이드오프, 도구의 제약) | 결정이 적용된 코드나 스크립트 바로 옆 주석. 코드가 없는 결정(제품 가정, 계정 구조)은 그 결정을 바꿀 때 고칠 문서의 한 문단 |
| IAM 권한 정책의 의도 | `infra/bootstrap/policy-tests/`의 테스트 |
| 운영 절차 | `scripts/`의 스크립트. `docs/operations.md`에는 스크립트로 만들 수 없는 순서와 사용법만 둔다 |
| GitHub 환경 설정 | `scripts/check-github-settings.sh`의 기대값 |
| 적용 상태 | bootstrap은 `main`(merge 직후 적용), 서비스 기반은 GitHub Deployments |
| 변경 이력과 실행 결과 | PR 본문과 PR 댓글 |

## AI 작업 기록

- PR 하나가 작업 하나다. 목표·변경·검증·비용과 운영 영향·남은 사항을 `.github/pull_request_template.md`에 맞춰 PR 본문에 쓴다. AI가 작성한 계획과 코드는 사람의 PR 리뷰를 거친다.
- merge 후 운영 작업(bootstrap 적용, GitHub 설정 변경, workflow 실행)의 결과는 해당 PR에 댓글로 남긴다. 상태·완료일·merge commit은 파일에 쓰지 않는다.
