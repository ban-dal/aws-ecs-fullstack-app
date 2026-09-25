# 작업 지침

AI가 기획·디자인·앱·인프라·운영 문서를 함께 유지하는 실험 프로젝트다. 작업 전 `README.md`와 관련 문서를 읽고, 코드와 문서가 어긋나면 같은 변경에서 고친다.

## 문서

- [`docs/product.md`](docs/product.md): 목표, 사용자 동작
- [`docs/design.md`](docs/design.md): 화면, 접근성
- [`docs/architecture.md`](docs/architecture.md): 전체 구조
- [`docs/operations.md`](docs/operations.md): 운영 절차
- [`infra/README.md`](infra/README.md): Terraform 구조와 규칙

## 규칙

- 공개 저장소다. 계정 ID, state 버킷, 개인 연락처는 코드·문서·PR·스크립트 출력에서 `<account-id>`, `<state-bucket>`처럼 가린다.
- Terraform state, `.tfvars`, 비밀, AWS 자격 증명은 커밋하지 않는다. GitHub Actions는 OIDC를 쓴다.
- `preprod`와 `prod`는 state key와 리소스 이름을 나누고, 서로 영향을 주는지 검토한다.
- AWS 비용이 늘면 PR에 예상 비용, 무료 플랜 영향, 종료 방법, plan 결과를 쓴다.

## 테스트

- 테스트 제목은 한국어로 입력과 결과를 쓴다. 예: `GET /api/health는 ok 상태를 반환한다`
- 테스트는 사용자 동작이나 회귀 위험만 검증한다. 단순 속성·클래스 확인은 쓰지 않는다.

## 적용

| 대상 | 방법 |
| --- | --- |
| 서비스 리소스 | merge 후 `main`에서 `Apply service foundation` workflow |
| `infra/bootstrap` | merge 후 로컬에서 `scripts/bootstrap.sh` |

- plan 범위가 PR 본문과 다르거나 정책 테스트가 실패하면 적용하지 않고 묻는다.
- merge 후 운영 작업과 로컬 긴급 변경의 결과는 PR 댓글에 남기고, 긴급 변경은 코드에 반영한다.

## 검증

| 변경 | 실행 |
| --- | --- |
| 앱 | `pnpm typecheck`, `pnpm build` |
| Terraform | `terraform fmt -check`, 수정한 루트의 `terraform validate` |
| `infra/bootstrap` | `scripts/bootstrap.sh plan`의 요약과 정책 테스트 결과를 PR에 쓴다. 정책 의도가 바뀌면 같은 PR에서 `infra/bootstrap/tests/`를 고친다 |
| GitHub 환경·변수 | `scripts/check-github-settings.sh`. 기대값이 바뀌면 같은 PR에서 스크립트를 고친다 |

## 사실의 원천

같은 사실은 원천 한 곳에만 쓰고 나머지는 링크한다. 날짜별 기록, 결정 로그, 상태·완료일·merge commit은 파일에 두지 않는다.

| 정보 | 원천 |
| --- | --- |
| 선언된 내용 | Terraform·workflow·스크립트 코드 |
| 결정 이유 | 해당 코드 옆 주석. 코드가 없는 결정은 관련 문서의 한 문단 |
| IAM 정책 의도 | `infra/bootstrap/tests/` |
| 운영 절차 | `scripts/`. `docs/operations.md`에는 스크립트로 만들 수 없는 순서와 사용법만 둔다 |
| GitHub 환경 설정 | `scripts/check-github-settings.sh`의 기대값 |
| 적용 상태 | bootstrap은 `main`, 서비스는 GitHub Deployments |
| 변경 이력과 실행 결과 | PR 본문과 댓글 |
