# Task 004: 보호된 서비스 기반 적용 경로

| 항목 | 값 |
| --- | --- |
| PR | [#4 · 보호된 서비스 기반 적용 경로](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/4) |
| 작업 브랜치 | `feat/protected-apply` |
| 상태 | 진행 중: 코드·GitHub 환경 검증 완료, PR CI·검토 대기 |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 003에서 선언한 VPC·서브넷·보안 그룹·ECR을 실제로 적용할 수 있는 경로를 준비한다. PR plan과 실제 apply에 서로 다른 OIDC 역할을 사용하고, merge된 `main`에서만 수동 실행하며, `preprod`와 `prod`를 별도 state·역할·GitHub 환경으로 보호한다.

이번 PR의 완료 기준은 적용 역할·workflow 코드, GitHub 환경 보호 규칙, Terraform 정적 검사와 bootstrap plan, 재구성·비용·복구 절차, PR 검토·merge다. **AWS bootstrap 및 서비스 리소스 apply는 이 PR에서 실행하지 않는다.**

## 작업 내용과 결정

- `infra/bootstrap/apply.tf`: `preprod-apply`와 `prod-apply` 환경 subject만 신뢰하는 별도 OIDC 역할, 각 환경의 S3 state key 쓰기·잠금 권한, 서울 리전의 현재 네트워크 작업과 환경별 ECR 저장소 작업을 선언한다. EC2 실행, ALB, NAT, IAM 수정 권한은 부여하지 않는다.
- `.github/workflows/apply-foundation.yml`: `workflow_dispatch`와 `main` ref로 제한한다. 먼저 기존 plan 역할과 `*-plan` 환경에서 변경을 출력한다. 이어 `*-apply` 환경에서 다시 plan하고 모듈의 신규 생성 최대 17개만 허용한 뒤 동일 runner의 저장된 plan을 적용한다. plan 파일은 artifact로 업로드하지 않는다.
- `preprod-apply`, `prod-apply` GitHub 환경은 `main` 브랜치만 허용하고 `ban-dal`의 수동 승인을 요구한다. 사용자가 선택한 1인 운영 방식으로 자기 승인을 허용하며, 독립된 두 번째 검토자는 없다. 각 환경의 `AWS_APPLY_ROLE_ARN` 변수는 해당 역할의 예정 ARN으로 등록하고 읽어 확인했다. 역할 자체는 아직 없다.
- 최초 적용 역할 자체는 아직 AWS에 없으므로, 이 PR merge 후 기존 관리자 자격 증명으로 bootstrap plan을 검토하고 한 번 적용해야 한다. 이 초기 권한 구성은 일반 서비스 apply workflow와 별도로 기록한다.

## 재구성 절차

1. Task 001의 S3 bootstrap state, Task 002의 `*-plan` 환경·저장소 변수, Task 003의 서비스 기반 코드를 확인한다.
2. 이 PR에서 bootstrap plan이 의도한 IAM 변경만 포함하는지 검토한다. PR merge 전에는 적용하지 않는다.
3. [운영 가이드의 최초 권한 준비와 적용](../operations.md#5-보호된-서비스-기반-적용)에 따라 bootstrap IAM 변경을 먼저 적용하고, 두 역할 ARN과 GitHub 적용 환경 변수를 대조한다.
4. `main`에서 workflow를 `preprod`로 수동 실행한다. plan 로그를 읽고 적용 환경을 승인한다. preprod를 확인한 뒤에만 prod를 별도로 실행한다.

## 검증과 운영 영향

- 로컬 `terraform fmt -check -recursive infra`, bootstrap·plan validate, workflow YAML·모든 shell 단계 구문 검사와 `git diff --check`가 통과했다. 실제 preprod plan JSON으로 생성 제한을 통과시켰고, 변경·다른 모듈·17개 초과 생성은 각각 차단되는 것을 확인했다.
- AWS 원격 bootstrap plan은 IAM 역할 2개와 정책 3개 생성, 기존 리소스 변경·삭제 0개로 확인했다. 실제 적용 전 재실행해 결과를 다시 확인한다.
- 두 GitHub 적용 환경의 `ban-dal` 승인자, 자기 승인 허용, `main` 브랜치 제한과 역할 ARN 변수를 API로 다시 읽어 확인했다. workflow는 아직 `main`에 merge되지 않아 실제 실행하지 않았다.
- 현재 workflow는 생성만 허용하므로 드리프트 수정·리소스 교체·삭제는 차단한다. 이후 변경은 별도 PR에서 권한과 승인 절차를 확장한다.
- 코드와 GitHub 환경 설정만으로는 AWS 리소스 비용이 늘지 않는다. 실제 서비스 기반을 적용하면 환경별 17개 리소스가 생성될 수 있다. VPC·Internet Gateway 자체에는 추가 요금이 없지만 ECR 이미지 저장량·전송량과 S3 state 요청에는 사용량에 따른 비용이 생길 수 있다. NAT, EC2, ALB, 퍼블릭 IPv4는 여전히 만들지 않는다.
- 실제 AWS 적용 여부: 미적용.

## 남은 사항과 다음 Task

PR merge 후 최초 bootstrap IAM 적용을 명시적으로 승인받아 실행하고 결과를 다음 Task에서 기록한다. 그다음 보호된 `preprod` 적용과 리소스 확인, 필요 시 `prod` 적용을 진행한다. 앱 공개 경로는 별도 비용 검토 후 추가한다.
