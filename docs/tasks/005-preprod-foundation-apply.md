# Task 005: bootstrap IAM 및 preprod 기반 적용

| 항목 | 값 |
| --- | --- |
| PR | 생성 후 링크 입력 |
| 작업 브랜치 | `feat/preprod-foundation-apply` |
| 상태 | 진행 중: bootstrap plan 검토 완료, 적용 승인 대기 |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 004에서 준비한 IAM 역할을 실제 AWS에 반영하고, 보호된 GitHub Actions 경로에서 `preprod` 서비스 기반을 처음 적용한다. 계정·state·역할·리소스 결과를 확인해 같은 환경을 재구성할 수 있는 실행 기록을 남긴다. `prod` 리소스 생성은 이번 Task의 범위 밖이다.

완료 기준은 사전 plan과 사용자 승인, IAM bootstrap 적용 및 결과 확인, `preprod-plan`·`preprod-apply` 환경별 수동 승인, 서비스 기반 17개 생성 결과와 사후 plan 확인, 운영 문서 갱신, PR 검토·merge다.

## 작업 내용과 결정

- PR #4가 2026-09-23 merge됐고 앱 CI·Terraform validate·환경별 plan이 모두 성공한 것을 확인했다.
- 추가 worktree 없이 원본 프로젝트 폴더의 merge된 `main`에서 이 브랜치를 만들었다.
- AWS 계정 `065768154598`, Terraform `1.14.0`과 원격 bootstrap state를 확인했다. 관리자 자격 증명은 일회성 IAM 준비에만 사용하며 서비스 리소스는 보호된 workflow로 적용한다.
- 저장된 bootstrap plan은 `aws_iam_role.foundation_apply` 2개, `aws_iam_role_policy.foundation_apply` 2개, `aws_iam_role_policy.foundation_plan_read` 1개 **생성**, 기존 리소스 변경·삭제 0개다. 실제 적용은 사용자 승인 후에만 진행한다.

## 재구성 절차

1. [Task 001](001-terraform-foundation.md)부터 [Task 004](004-protected-foundation-apply.md)까지의 코드·GitHub 환경·state를 복원한다. `aws sts get-caller-identity`로 계정 `065768154598`을 확인한다.
2. [운영 가이드 5절](../operations.md#5-보호된-서비스-기반-적용)의 최초 IAM 권한 준비 명령으로 원격 bootstrap을 초기화하고 저장 plan을 확인한다. 역할 2개와 정책 3개 생성 외의 변경이 있으면 적용을 중단한다.
3. 승인된 bootstrap plan을 적용하고 두 역할 ARN을 GitHub 적용 환경 변수와 대조한다. 관리자 프로필로 서비스 기반을 직접 적용하지 않는다.
4. merge된 `main`에서 `preprod` workflow를 수동 실행한다. GitHub의 `preprod-plan`과 `preprod-apply`는 각각 수동 승인한다. 적용 후 state와 AWS 리소스, 변경 없음 plan을 확인한다.
5. 종료가 필요하면 후속 종속 리소스를 먼저 제거하고 ECR 이미지를 비운 뒤 별도 검토된 destroy 절차를 사용한다. bootstrap state 버킷은 유지한다.

## 검증과 운영 영향

- bootstrap `terraform validate` 통과. 원격 저장 plan: 5개 생성, 변경·삭제 0개. 저장 plan 파일은 임시 디렉터리에 두고 작업 종료 시 삭제한다.
- 실제 AWS 적용 여부: 승인 대기. `preprod` 기반과 `prod` 기반은 아직 생성하지 않았다.
- IAM 역할·정책에는 별도 사용 시간 요금이 없다. 서비스 기반 적용 시 VPC·Internet Gateway와 빈 ECR 저장소가 생긴다. S3 state 요청과 이후 ECR 이미지 저장·전송은 사용량에 따라 비용이 발생할 수 있다. NAT, EC2, ALB, 퍼블릭 IPv4는 만들지 않는다. 계정의 실제 Free plan·크레딧은 Billing에서 확인한다.

## 남은 사항과 다음 Task

`preprod` 실측 결과와 비용을 확인한 뒤 `prod` 기반 적용 여부를 결정한다. 이후 ECS/EC2, ALB, HTTPS를 공개 앱 비용 스위치 기본값 `false`로 설계한다.
