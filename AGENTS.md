# 작업 지침

이 저장소는 AI가 기획, 디자인, 애플리케이션, 인프라와 운영 문서를 함께 유지하는 실험 프로젝트다. 변경 전 `README.md`와 관련 `docs/` 문서를 읽고, 코드와 문서가 어긋나면 같은 변경에서 함께 고친다.

## 기본 원칙

- 목표와 사용자 동작은 `docs/product.md`, 화면과 접근성 기준은 `docs/design.md`, 리소스와 경계는 `docs/architecture.md`, 배포와 장애 대응은 `docs/operations.md`를 기준으로 한다.
- Next.js 앱은 `apps/web`에 둔다. 후속 Terraform 구현은 `infra/bootstrap`과 환경별 live 구성으로 나누고, 새 공유 패키지는 `packages/*`에 둔다.
- 현재는 pnpm workspaces만 사용한다. 빌드 단계가 복잡해질 때 Turbo를 추가한다.
- AWS 리소스나 비용을 늘리는 변경은 예상 비용, 종료 방법, 무료 플랜 영향, PR plan 결과를 설명한다. `enable_public_app`의 기본값은 `false`로 유지한다.
- Terraform state, `.tfvars`, 계정 비밀, AWS 자격 증명은 커밋하지 않는다. GitHub Actions는 OIDC를 사용한다.
- Terraform을 구현할 때 `preprod`와 `prod`는 서로 다른 S3 state key와 리소스 이름을 유지한다. 한 환경 변경이 다른 환경에 영향을 주는지 검토한다.
- 향후 `terraform apply`는 PR 리뷰와 merge 이후 GitHub 환경 보호 규칙을 통과해 실행한다. 로컬 긴급 변경은 `docs/operations.md`에 기록하고 코드에 반영한다.

## 테스트 및 검증

- 테스트를 새로 쓰거나 이름을 바꿀 때 `it`/`test` 제목은 한국어로 입력·상황과 예상 결과를 모두 포함한다. 예: `GET /api/health는 ok 상태를 반환한다`.
- 요청 범위의 실제 사용자 동작 또는 회귀 위험을 검증하는 테스트만 추가한다. 낮은 영향의 단순 속성·클래스 확인 테스트는 만들지 않는다.
- 앱 변경에는 `pnpm typecheck`, `pnpm build`를 실행한다. Terraform이 추가되면 `terraform fmt -check -recursive infra`와 `terraform validate`도 실행한다.
- 브라우저 동작은 필요한 경우 실제 브라우저에서 확인하고 검증 범위를 명시한다.

## AI 작업 기록

큰 변경은 목적, 선택한 대안, 구현, 검증, 비용과 남은 제약을 PR에 남긴다. 새로운 서비스나 제품 가정을 도입할 때는 `docs/`에 결정과 근거를 기록한다. AI가 작성한 계획과 코드는 사람의 PR 리뷰를 거쳐야 한다.
