# 인프라 구성

- `bootstrap`: S3 state 버킷, GitHub OIDC plan 역할, 선택형 월간 비용 Budget. AWS 적용은 별도 운영 단계다.
- `plan`: AWS 계정 식별과 환경별 원격 state를 유지하는 루트 구성. `live` 모듈을 호출해 서비스 기반을 plan한다.
- `live`: VPC·서브넷·라우팅·보안 그룹·비공개 ECR 모듈. 현재 코드만 준비했으며 AWS에는 적용하지 않았다.

`bootstrap/apply.tf`는 환경별 서비스 기반 적용 역할을 선언한다. 이 역할이 AWS에 생성된 뒤 `.github/workflows/apply-foundation.yml`에서 현재 기반 리소스의 신규 생성만 허용한다. 최초 역할 생성은 PR merge 후 기존 관리자 프로필로 bootstrap을 한 번 적용해야 한다.

ECS/EC2, ALB, HTTPS는 후속 PR에서 추가한다. 운영 절차는 `docs/operations.md`를 따른다.
