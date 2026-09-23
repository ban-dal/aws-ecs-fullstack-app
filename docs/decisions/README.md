# 결정 기록

코드와 설정만 보고는 알 수 없는 선택과 그 이유를 남긴다. 무엇이 적용됐는지는 코드와 [README의 현재 상태](../../README.md#현재-상태)가, 언제 어떻게 적용했는지는 PR과 PR 댓글이 기준이다.

| 번호 | 결정 | 상태 |
| --- | --- | --- |
| [0001](0001-single-account-environments.md) | 한 AWS 계정 안에서 `preprod`·`prod`를 논리적으로 분리 | 채택 |
| [0002](0002-github-oidc-approvals.md) | GitHub OIDC와 1인 환경 승인 | 채택 |
| [0003](0003-protected-apply.md) | 서비스 기반은 `main`의 보호된 workflow로만 적용 | 채택 |
| [0004](0004-human-operator-access.md) | 사람의 운영 접근은 IAM 사용자와 MFA 역할 | 채택 |
| [0005](0005-github-role-boundary.md) | GitHub 역할 permissions boundary와 환경 태그 격리 | 채택 |
| [0006](0006-work-records.md) | 작업 기록은 PR과 결정 기록으로 | 채택 |

## 작성 규칙

- 결정 하나에 파일 하나, 20줄 안팎으로 쓴다. 맥락·결정·결과와 제약·다시 볼 조건을 적는다.
- 실행 로그, plan 개수, 적용 결과는 적지 않는다. 그런 증거는 PR 본문과 댓글에 남긴다.
- 결정을 바꾸면 새 번호로 쓰고, 이전 기록의 상태를 `대체됨: NNNN`으로 바꾼다.
