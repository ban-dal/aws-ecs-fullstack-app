# 인프라 구성

- `bootstrap`: S3 state 버킷, GitHub OIDC 환경별 plan·apply 역할과 공통 permissions boundary, 선택형 월간 비용 Budget. AWS 적용은 별도 운영 단계다.
- `plan`: AWS 계정 식별과 환경별 원격 state를 유지하는 루트 구성. `live` 모듈을 호출해 서비스 기반을 plan한다.
- `live`: VPC·서브넷·라우팅·보안 그룹·비공개 ECR 모듈.

`bootstrap/apply.tf`는 환경별 서비스 기반 적용 역할을, `bootstrap/boundary.tf`는 모든 GitHub 역할의 permissions boundary를, `bootstrap/operator.tf`는 사람의 비루트 운영 사용자와 MFA 필수 역할을 선언한다. 서비스 기반은 `.github/workflows/apply-foundation.yml`로, bootstrap은 로컬 저장 plan으로 적용한다. 적용 주체와 절차는 [운영 가이드](../docs/operations.md)를, 적용 상태는 [README](../README.md#현재-상태)를 본다.

ECS/EC2, ALB, HTTPS는 후속 PR에서 추가한다.
