# Task 003: 서비스 기반 네트워크와 ECR

| 항목 | 값 |
| --- | --- |
| PR | [#3 · 서비스 기반 네트워크와 ECR](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/3) |
| 작업 브랜치 | `feat/service-infra-foundation` |
| 상태 | 진행 중: Terraform 코드 완료, PR plan 검증 대기 |
| 시작일 | 2026-09-23 |
| 완료일·merge commit | PR merge 후 기록 |

## 목표와 완료 기준

Task 002의 환경별 원격 state와 OIDC plan을 서비스 인프라의 첫 단계에 사용한다. `preprod`와 `prod` 각각에 독립된 VPC, 두 가용 영역의 공개·비공개 서브넷, 라우팅, 보안 그룹, 비공개 ECR 저장소를 선언한다. 이 단계에는 공개 앱과 실행 중인 컴퓨트 리소스가 없다.

완료 기준은 정적 검사, PR에서 두 환경의 실제 plan, 비용·종료 절차 기록, 사람의 PR 검토와 merge다. 이 Task에서는 AWS 리소스를 `apply`하지 않는다.

## 작업 내용과 결정

- `infra/plan`은 기존 S3 state key와 AWS 계정 확인을 유지하고, `infra/live`의 서비스 기반 모듈을 호출한다. 두 환경의 이름, CIDR, state를 분리한다.
- `preprod`는 `10.60.0.0/16`, `prod`는 `10.61.0.0/16`이다. 각 환경에 두 공개·두 비공개 서브넷을 만든다. 공개 라우트만 Internet Gateway로 향하고 NAT는 만들지 않는다.
- 공개 서브넷에서도 자동 퍼블릭 IP 할당을 끈다. ALB 보안 그룹에는 아직 공개 ingress가 없다. ECS 호스트 보안 그룹은 미래 ALB 보안 그룹에서 오는 동적 bridge 포트만 받고 SSH는 열지 않는다.
- 환경별 비공개 ECR 저장소는 불변 이미지 태그와 SSE-S3 암호화를 사용한다. 최근 이미지 5개만 유지하고, 이미지가 남아 있을 때 저장소를 강제로 삭제하지 않는다.
- `infra/bootstrap`에 plan 역할의 VPC·ECR 읽기 정책을 선언했다. 첫 서비스 `apply` 전에 bootstrap 변경을 승인된 절차로 적용해야, 이후 PR plan이 기존 리소스를 refresh할 수 있다.

## 재구성 절차

1. [Task 001](001-terraform-foundation.md)의 bootstrap과 [Task 002](002-github-pr-plan-setup.md)의 GitHub 환경·변수를 복원한다.
2. 대상 AWS 계정에서 `ap-northeast-2a`, `ap-northeast-2c`를 사용할 수 있는지 확인한다. 다르면 `availability_zones` 입력을 두 환경에서 같은 순서로 지정한다. 적용 후 AZ 순서를 바꾸면 서브넷 주소와 리소스 교체가 발생할 수 있다.
3. [운영 가이드 4절](../operations.md#4-서비스-기반-네트워크와-ecr)의 순서로 PR plan을 확인한다. 이후 승인된 bootstrap 정책 적용, `preprod` 기반 적용, `prod` 기반 적용 순서를 지킨다. 현재 저장소에는 apply 워크플로가 없으므로 이 Task에서는 3단계 이후 실제 적용을 진행하지 않는다.
4. 종료할 때는 앱의 ECS·ALB 등 종속 리소스를 먼저 제거하고, ECR 이미지를 비운 뒤 각 환경 state에서 기반 리소스를 destroy한다. bootstrap state 버킷은 별도 수명 주기로 유지한다.

## 검증과 운영 영향

- 로컬 `terraform fmt -check -recursive infra`, `infra/bootstrap`·`infra/plan` init·validate 결과를 기록한다.
- PR의 `preprod`·`prod` plan에서 계정, state key, 리소스 개수와 변경 범위를 확인한다. 각 환경의 plan은 해당 환경의 state만 사용한다.
- VPC와 Internet Gateway 자체에는 추가 요금이 없지만 ECR 이미지 저장량과 전송량은 사용량에 따라 과금된다. 이 Task의 코드만 merge하면 AWS 리소스나 새 비용은 발생하지 않는다. 퍼블릭 IPv4, NAT Gateway, EC2, ALB는 만들지 않는다.
- 실제 AWS 적용 여부: 미적용.

## 남은 사항과 다음 Task

Task 004에서는 보호된 `apply` 워크플로와 최소 권한 실행 역할을 먼저 설계하고, bootstrap 읽기 정책을 적용한 다음 기반 리소스를 `preprod`에서 검증한다. 그 뒤 ECS/EC2, ALB, HTTPS를 비용 스위치 `enable_public_app=false`로 단계적으로 추가한다.
