# Task 007: 운영자 MFA 자기 관리

| 항목 | 값 |
| --- | --- |
| PR | 생성 후 링크 입력 |
| 작업 브랜치 | `fix/operator-mfa-management` |
| 상태 | 진행 중 |
| 시작일 | 2026-09-24 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 006에서 만든 IAM 사용자가 패스키를 등록한 후 인증 앱(TOTP) MFA를 추가하려 할 때 `iam:DeactivateMFADevice` 권한 누락으로 막혔다. AWS CLI/API는 패스키 MFA를 지원하지 않아 TOTP가 있어야 MFA 조건이 있는 운영 역할을 수임할 수 있다. 사용자가 자신의 MFA 장치만 관리하도록 권한을 보완하고, 비루트 CLI 역할 수임과 변경 없는 bootstrap plan까지 확인한다.

## 작업 내용과 결정

- `iam:DeactivateMFADevice`는 자기 IAM 사용자 ARN에만, `iam:DeleteVirtualMFADevice`는 자기 이름의 가상 MFA ARN에만 허용한다. 두 삭제성 작업은 `aws:MultiFactorAuthPresent=true`인 세션으로 제한한다.
- 기존 패스키는 콘솔 로그인용으로 유지한다. CLI 역할 수임에는 별도 TOTP MFA 장치 ARN을 사용한다. QR 코드·OTP·복구 정보는 Git과 문서에 저장하지 않는다.
- PR의 `infra/plan`은 bootstrap IAM 정책 변경을 보여주지 않는다. PR merge 후 관리자 세션으로 bootstrap plan을 확인하고 적용한다.

## 재구성 절차

1. [운영 가이드의 비루트 CLI 절차](../operations.md#6-비루트-운영-주체)를 따른다.
2. PR merge 후 bootstrap 저장 plan에서 `aws_iam_user_policy.operator` 1개 수정, 생성·삭제 0개만 있는지 확인하고 적용한다.
3. 사용자가 콘솔에서 이름 `aws-fullstack-lab-operator`의 자기 TOTP MFA를 추가한다. `mfa_serial`을 그 TOTP ARN으로 설정한 비루트 CLI 프로필로 역할 수임을 확인한다.
4. 비루트 역할로 bootstrap plan을 실행해 변경 없음(종료 코드 0)을 확인한다. 실패 시 root 세션은 유지하고 MFA 등록·역할 신뢰 정책·프로필을 순서대로 확인한다.

## 검증과 운영 영향

- Terraform fmt·validate와 IAM 정책 diff가 통과했다. 실제 원격 bootstrap plan은 `aws_iam_user_policy.operator` 1개 수정, 생성·삭제 0개였다. PR merge 후 같은 범위를 재확인한다.
- IAM 정책 수정은 AWS 리소스 시간당 비용을 늘리지 않는다. S3 state 요청·버전은 기존 과금 범위다.
- 사용자가 인증 앱을 등록할 때까지 root를 일상 운영에서 제거했다고 기록하지 않는다.

## 남은 사항과 다음 Task

다음 Task는 PR 변경 파일과 환경별 plan 동작을 한 댓글에 표시해 Terraform 리뷰 가시성을 높인다.
