# Task 008: bootstrap IAM 권한 경계

| 항목 | 값 |
| --- | --- |
| PR | 생성 후 링크 입력 |
| 작업 브랜치 | `feat/bootstrap-iam-boundary` |
| 상태 | 진행 중 |
| 시작일 | 2026-09-24 |
| 완료일·merge commit | PR merge 후 입력 |

## 목표와 완료 기준

2026-09-24 Terraform 리뷰에서 bootstrap IAM의 권한 경계가 문서의 의도보다 넓다는 점을 확인했다. 운영 역할은 GitHub 역할의 정책·신뢰 정책을 바꿔 계정 관리자 수준 권한을 얻을 수 있다. `preprod` 적용 역할은 같은 리전의 `prod` 네트워크를 바꿀 수 있고, 공유 plan 역할은 두 환경 state를 모두 읽는다. `prod` 적용 전에 이 경계를 좁힌다.

- GitHub plan·apply 역할에 permissions boundary를 두고, 운영 역할이 boundary를 제거·교체하지 못한다.
- 환경별 적용 역할의 EC2 변경을 `Environment` 태그로 제한해 다른 환경 리소스를 변경·삭제하지 못한다.
- plan 역할을 환경별로 나눠 각 PR plan이 자기 환경 state만 읽는다.
- bootstrap provider에 `allowed_account_ids`를 두고 S3 backend 블록을 커밋한다.
- state 버킷에 이전 버전 만료 규칙을 두고, 환경 목록·ECR 이름 중복과 태그를 정리한다.
- PR merge 후 저장 plan을 확인·적용하고, 적용 역할로 `preprod` 사후 plan이 변경 없음인지 확인한다.

## 작업 내용과 결정

- 이 브랜치의 첫 변경에서 Task 007 완료일·merge commit과 2026-09-24 root 적용·비루트 검증 기록을 [운영 가이드](../operations.md#2026-09-24-task-007-적용과-비루트-검증-기록)에 반영했다. Terraform은 캐시된 역할 세션을 받는 `aws-fullstack-operator-terraform` 프로필로 실행하도록 CLI 절차를 고쳤다.
- boundary 정책 생성과 운영 역할 정책의 Deny 추가는 운영 역할 권한 밖이므로 root 세션 적용이 한 번 필요하다. 구현 후 그 범위를 저장 plan으로 확인한다.

## 재구성 절차

1. 구현 후 기록한다.

## 검증과 운영 영향

- 구현 후 기록한다. IAM 정책·S3 lifecycle 규칙은 시간당 요금이 없다.

## 남은 사항과 다음 Task

- Task 009: 적용 workflow의 신규 생성 전용 검사를 삭제·교체 차단 중심으로 재정의하고, 승인한 plan과 적용 plan의 일치 확인, 액션 SHA 고정, `infra/plan`의 `allowed_account_ids`, PR plan 댓글을 추가한다.
- Task 010: ECR `scan_on_push`, 보안 그룹 규칙 분리, provider `default_tags`를 보호된 `preprod` 적용으로 반영한다.
