# 인프라 구성

- `bootstrap`: S3 state 버킷, GitHub OIDC plan 역할, 선택형 월간 비용 Budget. AWS 적용은 별도 운영 단계다.
- `plan`: 비용을 발생시키는 리소스 없이 AWS 계정 식별과 환경별 원격 state 연결을 검증하는 PR plan 구성.

VPC와 앱 서비스는 후속 PR에서 추가한다. 운영 절차는 `docs/operations.md`를 따른다.
