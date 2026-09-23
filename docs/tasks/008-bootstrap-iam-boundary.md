# Task 008: bootstrap IAM 권한 경계

| 항목 | 값 |
| --- | --- |
| PR | [#8 · bootstrap IAM 권한 경계](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/8) |
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
- state 버킷에 이전 버전 만료 규칙을 두고, 환경 목록·ECR 이름 중복을 정리한다.
- PR merge 후 저장 plan을 확인·적용하고, GitHub plan 변수를 환경별로 바꾼 뒤 `preprod` plan·apply가 변경 없음인지 확인한다.

## 작업 내용과 결정

- 이 브랜치의 첫 변경에서 Task 007 완료일·merge commit과 2026-09-24 root 적용·비루트 검증 기록을 [운영 가이드](../operations.md#2026-09-24-task-007-적용과-비루트-검증-기록)에 반영했다. Terraform은 캐시된 역할 세션을 받는 `aws-fullstack-operator-terraform` 프로필로 실행하도록 CLI 절차를 고쳤다.
- `infra/bootstrap/boundary.tf`: 관리형 정책 `aws-fullstack-lab-github-boundary`를 추가했다. 환경 state 경로 S3 객체, state 버킷 목록, 서울 리전 `ec2:*`·`ecr:*`만 허용한다. 액션 단위 제한은 역할 정책이 맡고 boundary는 서비스 단위 상한만 둔다. 후속 서비스를 추가할 때마다 boundary를 넓히는 PR과 root 적용이 필요하지만, 그 확장을 사람이 검토하는 지점으로 삼는다.
- `infra/bootstrap/main.tf`: 공유 `aws-fullstack-lab-plan` 역할을 `aws-fullstack-lab-<environment>-plan`으로 나눴다. 각 역할은 자기 `*-plan` 환경 subject만 신뢰하고 자기 state 읽기·잠금과 VPC·ECR refresh 권한만 가진다. state 버킷에 이전 버전 90일 후 만료(최근 10개 유지)와 미완료 multipart upload 7일 후 정리 규칙을 추가했다. 환경 목록, ECR ARN, 기반 읽기 액션을 `locals`로 모았다.
- `infra/bootstrap/apply.tf`: 적용 역할의 EC2 생성은 `aws:RequestTag/Environment`, 부모 VPC와 기존 리소스 변경·삭제는 `aws:ResourceTag/Environment`로 제한했다. 생성 시 태그는 `ec2:CreateAction`으로만 허용하고, 기존 리소스의 `Environment` 태그 변경·제거를 막는다. 태그가 없는 보안 그룹 규칙 ARN은 별도 statement로 허용하고 부모 보안 그룹 태그를 검사한다.
- `infra/bootstrap/operator.tf`: 운영 역할에 boundary 읽기 권한과, GitHub 역할의 boundary 제거·다른 boundary로 교체·boundary 없는 재생성을 거부하는 Deny를 추가했다. Deny 대상은 삭제 후 재생성도 막도록 고정 이름 ARN으로 만든다.
- `infra/bootstrap/versions.tf`: `expected_account_id` 변수와 provider `allowed_account_ids`를 추가했다. `backend.s3.tf`를 커밋하고, 새 계정 첫 apply는 Git에서 제외되는 `backend_override.tf`로 local backend를 쓰도록 바꿨다.
- `.github/workflows/terraform.yml`: plan 역할을 환경 변수로 받도록 job 조건에서 `AWS_PLAN_ROLE_ARN`을 빼고 역할 확인 단계를 추가했다. 적용 workflow의 plan 단계는 이미 환경 변수를 읽는다.
- boundary ARN은 이름으로 만든 local 값을 쓴다. 새 리소스 ARN을 참조하면 운영 역할 정책 JSON이 plan에서 "known after apply"로 가려진다. 같은 이유로 bootstrap `default_tags`는 이번 Task에서 제외했다. 모든 리소스의 태그가 바뀌면 IAM 정책 data source가 apply 시점으로 미뤄져 내용이 같은 정책도 변경으로 표시된다. 태그 통일은 Task 010에서 live 모듈과 함께 다룬다.

## 재구성 절차

1. [운영 가이드 7절](../operations.md#7-github-역할-권한-경계)의 PR merge 후 적용 절차를 따른다. `terraform.tfvars`에 `expected_account_id`를 추가한다.
2. root 세션의 bootstrap 저장 plan이 생성 6개·수정 5개·삭제 3개이고 적용 역할의 수정 속성이 `permissions_boundary`뿐인지 확인한 뒤 적용한다.
3. `plan_role_arns` 값을 `preprod-plan`·`prod-plan` 환경 변수 `AWS_PLAN_ROLE_ARN`에 등록하고 저장소 변수 `AWS_PLAN_ROLE_ARN`을 삭제한다.
4. 운영 역할 bootstrap plan, `preprod` 적용 workflow의 plan·apply가 모두 변경 없음인지 확인한다.

## 검증과 운영 영향

- `terraform fmt -check -recursive infra`, `terraform -chdir=infra/bootstrap validate`, `terraform -chdir=infra/plan validate`, `git diff --check`가 통과했다.
- 2026-09-24 root 세션의 원격 bootstrap 저장 plan(적용하지 않음)은 **생성 6개·수정 5개·삭제 3개**였다. 적용 역할 2개의 수정 속성은 `permissions_boundary`뿐이고 운영 역할 정책은 statement 3개 추가, 제거 0개다. apply 시점으로 미뤄진 data source는 없다.
- 저장 plan의 정책 JSON으로 IAM 정책 시뮬레이터(`simulate-custom-policy`)를 40개 사례에 실행해 모두 기대대로 나왔다. 확인한 내용은 다음과 같다.
  - preprod 적용 역할: 자기 환경 태그로 생성·변경·삭제 허용, prod VPC 안 생성·prod 리소스 변경·`Environment` 태그 변경과 제거·다른 리전 호출 거부, prod state·prod ECR 거부.
  - preprod plan 역할: 자기 state 읽기만 허용.
  - `*:*` 역할 정책에 boundary를 붙인 경우: IAM 역할 생성·STS 수임·bootstrap state·다른 리전 호출 거부.
  - 운영 역할: boundary 제거·교체·boundary 없는 역할 생성은 명시적 거부, boundary 정책 수정 거부, 같은 boundary 지정은 허용.
- 기존 preprod VPC·서브넷 4개·라우팅 테이블 2개·Internet Gateway·보안 그룹 2개에 모두 `Environment=preprod` 태그가 있어, 태그 조건이 기존 리소스 관리를 막지 않는다.
- 시뮬레이터는 API별 필수 리소스 유형을 스스로 판단하지 않는다. 적용 역할의 실제 쓰기 경로는 다음 실제 변경(Task 010 preprod 수정 또는 `prod` 최초 생성)에서 처음 사용된다.
- IAM 정책·역할·S3 lifecycle 규칙에는 시간당 요금이 없다. 이전 버전 만료로 state 버킷 저장량은 줄어든다.

## 남은 사항과 다음 Task

- Task 009: 적용 workflow의 신규 생성 전용 검사를 삭제·교체 차단 중심으로 재정의하고, 승인한 plan과 적용 plan의 일치 확인, 액션 SHA 고정, `infra/plan`의 `allowed_account_ids`, PR plan 댓글을 추가한다.
- Task 010: ECR `scan_on_push`, 보안 그룹 규칙 분리, provider `default_tags`(bootstrap 포함)를 보호된 `preprod` 적용과 root bootstrap 적용으로 반영한다.
