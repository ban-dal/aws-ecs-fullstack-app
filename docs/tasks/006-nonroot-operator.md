# Task 006: 비루트 AWS 운영 주체

| 항목 | 값 |
| --- | --- |
| PR | 생성 후 링크 입력 |
| 작업 브랜치 | `feat/nonroot-operator` |
| 상태 | 진행 중: 코드·운영 절차 작성, AWS 미적용 |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 001과 005의 초기 bootstrap은 계정 root 임시 세션으로 실행했다. 사람의 일상적인 콘솔·CLI 운영을 비루트 자격으로 옮기고, root는 계정 복구 등 불가피한 경우에만 사용한다. GitHub Actions는 이미 OIDC 역할을 사용하며 이번 Task에서 그 인증 경로는 바꾸지 않는다.

완료 기준은 Terraform에 운영 사용자와 MFA 필수 운영 역할을 선언하고, 비밀번호·MFA 정보가 state와 Git에 들어가지 않는 초기 등록 절차를 문서화하는 것이다. PR 검증·리뷰·merge 후 원격 bootstrap plan에서 변경 범위를 확인하고 적용한다. 실제 비루트 전환은 사용자의 콘솔 비밀번호·MFA 등록 및 역할 수임 검증까지 끝나야 완료된다.

## 작업 내용과 결정

- [PR #5](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/5)가 2026-09-23 merge된 `main`에서 원본 프로젝트 폴더에 이 브랜치를 만들었다. 별도 worktree는 만들지 않았다.
- `infra/bootstrap/operator.tf`에 IAM 사용자 `aws-fullstack-lab-operator`와 역할 `aws-fullstack-lab-bootstrap-operator`를 선언한다. 사용자에게는 CLI 임시 로그인 권한과 이 역할을 수임할 권한만 준다. 역할 신뢰 정책은 해당 사용자와 MFA 인증을 요구하며 세션은 최대 1시간이다.
- 역할 권한은 이 프로젝트의 state 버킷, GitHub OIDC 제공자, 기존 plan·apply 역할 관리와 운영 주체·Budget 읽기로 한정한다. 역할 자신의 정책 수정 권한은 주지 않는다. 프로젝트 plan·apply 역할 정책을 수정할 수 있으므로 높은 신뢰가 필요한 운영 자격이다.
- 콘솔 비밀번호·MFA 장치·액세스 키는 Terraform에 넣지 않는다. 최초 콘솔 로그인 설정과 MFA 등록은 사용자 본인이 수행한다. 장기 AWS 액세스 키는 만들지 않는다.
- 학습용 `preprod`와 `prod`는 현재 한 AWS 계정 안에서 VPC·state key·리소스 이름·GitHub 환경을 분리한다. 계정 분리는 이번 Task에서 진행하지 않는다. 현재 Free plan 계정을 Organizations에 가입시키면 AWS 안내에 따라 크레딧이 즉시 만료되고 유료 플랜으로 전환된다.

## 재구성 절차

1. [운영 가이드의 비루트 전환 절차](../operations.md#6-비루트-운영-주체)를 따른다. root MFA를 먼저 등록하고, 계정·원격 state와 저장 plan을 확인한다.
2. PR이 merge된 뒤 기존 관리자 자격으로 bootstrap plan에서 IAM 사용자 1개, 역할 1개, 사용자 정책 1개, 사용자 관리형 정책 연결 1개, 역할 정책 1개만 생성되는지 확인한 후 적용한다. 예상 범위가 다르면 중단한다.
3. 사용자가 콘솔 로그인 비밀번호와 MFA를 등록한다. 운영 프로필의 호출 주체가 `assumed-role/aws-fullstack-lab-bootstrap-operator`인지 확인하고, 이 프로필로 bootstrap의 `terraform plan -detailed-exitcode`가 변경 없음인지 확인한다.
4. root 로그인은 종료하고 비루트 프로필만 일상 운영에 사용한다. 실패하면 root로 반복 시도하기 전에 역할 신뢰 조건, MFA, CLI 프로필, IAM 권한을 읽기 전용으로 확인한다.

## 검증과 운영 영향

- `terraform fmt -check -recursive infra`, `terraform -chdir=infra/bootstrap validate`, `git diff --check`가 통과했다. 계정 `065768154598`의 기존 S3 원격 state를 읽은 bootstrap plan은 **5개 생성, 변경 0개, 삭제 0개**였다. 새 IAM 사용자·역할·사용자 정책·사용자 관리형 정책 연결·역할 정책만 생성 대상으로 확인했다. 저장 plan은 임시 디렉터리에서 즉시 삭제했다.
- AWS 실제 적용과 비루트 로그인·역할 수임 검증은 아직 하지 않았다. PR merge 전에는 적용하지 않는다.
- IAM 사용자·역할·정책 자체에는 별도 시간당 요금이 없다. S3 state의 버전·요청은 기존과 같이 사용량에 따른 비용 또는 크레딧 사용 가능성이 있다. Organizations를 만들거나 Free plan을 유료 플랜으로 전환하지 않는다.
- 종료 시 비루트 로그인을 다른 운영 경로로 대체한 뒤 사용자 콘솔 접근을 끄고 Terraform에서 해당 사용자·역할·정책을 제거한다. state 버킷과 GitHub OIDC 역할은 유지한다.

## 남은 사항과 다음 Task

비루트 전환이 검증되기 전까지 root를 대체 완료로 기록하지 않는다. 전환 후에는 실험용 `prod` 기반 적용 여부와 ECS/EC2·ALB·HTTPS의 비용 및 중지 절차를 별도 Task로 결정한다.
