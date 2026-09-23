# 인프라 구성

- `bootstrap`: S3 state 버킷, GitHub OIDC plan 역할, 선택형 월간 비용 Budget. AWS 적용은 별도 운영 단계다.
- `plan`: AWS 계정 식별과 환경별 원격 state를 유지하는 루트 구성. `live` 모듈을 호출해 서비스 기반을 plan한다.
- `live`: VPC·서브넷·라우팅·보안 그룹·비공개 ECR 모듈. `preprod`는 AWS에 적용했고 `prod`는 아직 적용하지 않았다.

`bootstrap/apply.tf`는 환경별 서비스 기반 적용 역할을 선언한다. Task 005에서 역할을 AWS에 생성했고 `.github/workflows/apply-foundation.yml`로 `preprod`의 현재 기반 리소스 신규 생성만 적용했다. `bootstrap/operator.tf`는 사람의 비루트 운영 사용자와 MFA 필수 bootstrap 역할을 선언한다. 운영 사용자 적용과 콘솔 비밀번호·MFA 등록은 [운영 가이드](../docs/operations.md#6-비루트-운영-주체)를 따른다.

ECS/EC2, ALB, HTTPS는 후속 PR에서 추가한다. 운영 절차는 `docs/operations.md`를 따른다.
