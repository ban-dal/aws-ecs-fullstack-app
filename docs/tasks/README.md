# Task 기록

이 디렉터리는 **PR 하나를 Task 하나**로 기록한다. 파일 번호는 Task 순서이며 GitHub PR 번호와는 별개다. Task 문서는 목표, 실제 변경, 검증, 클라우드 적용 결과와 재구성 절차를 남긴다. 현재 운영 상태와 상세 명령은 [운영 가이드](../operations.md)를 기준으로 한다.

## 목록

| Task | 목표 | PR | 상태 |
| --- | --- | --- | --- |
| [001 · Terraform 기반과 PR 검증](001-terraform-foundation.md) | S3 state·OIDC·Budget·환경별 plan 기반 | [#1](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/1) | 완료: 2026-09-23 merge |
| [002 · GitHub PR plan 환경 구성](002-github-pr-plan-setup.md) | 환경 보호·저장소 변수·실제 plan 검증 | [#2](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/2) | 완료: 2026-09-23 merge |
| [003 · 서비스 기반 네트워크와 ECR](003-service-foundation.md) | 환경별 VPC·서브넷·보안 그룹·ECR 코드와 PR plan | PR 생성 후 연결 | 진행 중 |

## 작성 흐름

1. 새 PR을 시작할 때 다음 순번의 `NNN-짧은-주제.md`를 [`_template.md`](_template.md)에서 만든다. PR을 열면 링크를 기록하고 PR 본문에도 Task 문서를 연결한다.
2. PR 작업 중 목표와 완료 기준, 실제 변경 파일, 선택 이유, 검증 결과, 비용·보안·복구 영향, 재구성 절차를 갱신한다. AWS 계정 비밀, 자격 증명, `.tfvars`, state 내용은 기록하지 않는다.
3. **PR merge를 Task 완료 시점**으로 삼는다. merge를 확인한 뒤 다음 Task 브랜치의 첫 변경에서 이전 문서에 완료일과 merge commit을 기록하고, 다음 Task 문서를 만들며 이 목록을 갱신한다. 다음 목표는 이전 Task의 `다음 Task` 항목을 출발점으로 삼아 실제 우선순위에 맞게 확정한다.
4. 다음 PR도 같은 방식으로 한 문서를 유지한다. GitHub PR 상태가 문서의 임시 상태보다 최신인 경우 GitHub 상태를 기준으로 한다.

초기 저장소 생성은 PR 없이 `main`에 반영되었으므로 별도 Task 번호를 붙이지 않았다. 그 기준 구성은 [README](../../README.md)와 [제품 문서](../product.md)에 기록되어 있다.
