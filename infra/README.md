# 인프라 구성

```
infra/
├── bootstrap/           # 루트: 계정·IAM. PR merge 후 사람이 scripts/bootstrap.sh로 적용
│   └── tests/           # IAM 정책 테스트
├── environments/
│   ├── preprod/         # 루트: preprod 서비스 리소스. Apply service foundation workflow로 적용
│   └── prod/            # 루트: prod 서비스 리소스. 같은 workflow로 적용
└── modules/             # AWS 서비스 이름으로 나눈 모듈
```

| 모듈 | 내용 | 호출하는 루트 |
| --- | --- | --- |
| [`budgets`](modules/budgets/main.tf) | 월간 비용 알림 | bootstrap |
| [`ecr-registry`](modules/ecr-registry/main.tf) | 레지스트리(계정) 단위 push 스캔 | bootstrap |
| [`ecr-repository`](modules/ecr-repository/main.tf) | 환경별 이미지 저장소와 lifecycle | preprod, prod |
| [`iam-github-oidc`](modules/iam-github-oidc/main.tf) | GitHub OIDC 제공자, GitHub 역할 boundary | bootstrap |
| [`iam-github-plan`](modules/iam-github-plan/main.tf) | 환경별 PR plan 역할 | bootstrap |
| [`iam-github-apply`](modules/iam-github-apply/main.tf) | 환경별 서비스 적용 역할 | bootstrap |
| [`iam-github-image`](modules/iam-github-image/main.tf) | 환경별 이미지 push 역할(main 브랜치만) | bootstrap |
| [`iam-ecs-roles`](modules/iam-ecs-roles/main.tf) | 환경별 ECS 호스트 역할(인스턴스 프로파일)과 태스크 실행 역할 | bootstrap |
| [`iam-operator`](modules/iam-operator/main.tf) | 사람의 IAM 사용자와 MFA 역할 | bootstrap |
| [`iam-service-linked-roles`](modules/iam-service-linked-roles/main.tf) | ECS·EC2 Auto Scaling 서비스 연결 역할 | bootstrap |
| [`route53-zone`](modules/route53-zone/main.tf) | 서비스 도메인 `aws.bandal.dev` 영역과 CAA | bootstrap |
| [`s3-terraform-state`](modules/s3-terraform-state/main.tf) | Terraform state 버킷 | bootstrap |
| [`vpc`](modules/vpc/main.tf) | VPC, 서브넷, Internet Gateway, 라우팅 | preprod, prod |
| [`vpc-security-groups`](modules/vpc-security-groups/main.tf) | ALB·ECS 호스트 보안 그룹과 규칙 | preprod, prod |

## 규칙

- **bootstrap과 환경 루트를 나눈다.** 적용하는 주체와 권한이 다르기 때문이다. `bootstrap`은 GitHub 역할 자체를 만들므로 사람이 적용하고, 환경 루트는 GitHub apply 역할이 적용한다. apply 역할은 boundary 때문에 IAM을 바꾸지 못한다.
- **환경마다 루트를 둔다.** preprod와 prod는 같은 모듈을 쓰지만 구성이 다르다(예: preprod는 단일 호스트와 IP 허용 목록). 조건문으로 한 루트에 섞지 않고, 각 환경의 `main.tf`가 그 환경의 구성을 그대로 보여 주게 한다. 두 환경에 공통인 변경은 두 루트를 같은 PR에서 고친다.
- **모듈 폴더 이름은 `<AWS 서비스>-<기능>`을 소문자 dash-case로 쓴다.** 기능이 하나뿐이면 서비스 이름만 쓴다(`vpc`, `budgets`). 새 모듈도 같은 규칙을 따른다. 예: `alb`, `acm`, `route53`, `ecs-cluster`, `ecs-service`, `lambda`.
- **모듈에는 `main.tf`, `variables.tf`, `outputs.tf` 세 파일만 둔다.** `main.tf` 맨 위 주석에 무엇을 왜 두는지 쓰고, locals도 `main.tf`에 둔다. `main.tf`가 너무 커지면 기능별로 모듈을 나눈다.
- **루트에는 `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`를 둔다.** `versions.tf`에는 terraform·provider·backend만, `main.tf`에는 모듈 호출과 모듈 사이에 넘기는 값만 둔다. 루트에 리소스를 직접 두지 않는다.
- **리소스 주소를 바꿀 때는 루트의 `moved.tf`에 `moved` 블록을 둔다.** 적용이 끝나면 다음 PR에서 지운다.
- **두 루트가 공유해야 하는 이름**은 한쪽에서 다른 쪽을 가리키는 주석을 단다. 예: ECR 저장소 이름과 서비스 기반 refresh용 읽기 액션(`bootstrap/main.tf`의 locals).

적용 주체와 절차는 [운영 가이드](../docs/operations.md), 적용 상태는 [README](../README.md#적용-상태-확인)를 본다. 권한 정책의 의도는 [`bootstrap/tests/`](bootstrap/tests/iam.test.mjs)의 테스트가 기준이다.
