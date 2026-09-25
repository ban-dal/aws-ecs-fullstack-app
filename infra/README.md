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
| [`ec2-ecs-host`](modules/ec2-ecs-host/main.tf) | 단일 ECS 호스트와 WireGuard 서버 | preprod |
| [`ec2-client-vpn`](modules/ec2-client-vpn/main.tf) | 인증서 기반 AWS Client VPN 엔드포인트와 단일 서브넷 연결 | preprod |
| [`ecs-cluster`](modules/ecs-cluster/main.tf) | ECS 클러스터 | preprod |
| [`ecs-preprod-web`](modules/ecs-preprod-web/main.tf) | 앱 태스크·서비스·로그 | preprod |
| [`iam`](modules/iam/main.tf) | GitHub OIDC, 공통 plan·apply·image 역할, 사람의 MFA 운영 역할, 공통 ECS 역할 | bootstrap |
| [`route53-zone`](modules/route53-zone/main.tf) | 서비스 도메인 `aws.bandal.dev` 영역과 CAA | bootstrap |
| [`s3-terraform-state`](modules/s3-terraform-state/main.tf) | Terraform state 버킷 | bootstrap |
| [`vpc`](modules/vpc/main.tf) | VPC, 서브넷, Internet Gateway, 라우팅 | preprod, prod |
| [`vpc-security-groups`](modules/vpc-security-groups/main.tf) | ALB·ECS 호스트·preprod VPN 보안 그룹과 규칙 | preprod, prod |

## 규칙

- **bootstrap과 환경 루트를 나눈다.** `bootstrap`은 GitHub 역할 자체를 만들므로 사람이 적용하고, 환경 루트는 공통 GitHub apply 역할이 적용한다. apply 역할은 AWS 관리형 `PowerUserAccess`로 IAM 외의 서비스를 다루고 ECS 역할을 넘길 수 있지만, IAM 역할을 만들거나 고칠 수 없다(서비스 연결 역할 생성만 허용). 환경 루트에 새 AWS 서비스를 추가해도 bootstrap을 먼저 바꾸지 않는다. 새 IAM 역할이 필요할 때만 bootstrap에서 만들고 apply의 `iam:PassRole` 대상에 더한다.
- **환경마다 루트를 둔다.** preprod와 prod는 같은 모듈을 쓰지만 구성이 다르다(예: preprod는 단일 호스트와 IP 허용 목록). 조건문으로 한 루트에 섞지 않고, 각 환경의 `main.tf`가 그 환경의 구성을 그대로 보여 주게 한다. 두 환경에 공통인 변경은 두 루트를 같은 PR에서 고친다.
- **모듈 폴더 이름은 `<AWS 서비스>-<기능>`을 소문자 dash-case로 쓴다.** IAM처럼 한 서비스의 접근 경로를 함께 관리할 때는 서비스 이름만 쓴다(`iam`, `vpc`, `budgets`). 새 모듈도 같은 규칙을 따른다. 예: `alb`, `acm`, `route53`, `ecs-cluster`, `ecs-service`, `lambda`.
- **모듈에는 `main.tf`, `variables.tf`, `outputs.tf` 세 파일만 둔다.** `main.tf` 맨 위 주석에 무엇을 왜 두는지 쓰고, locals도 `main.tf`에 둔다. 모듈은 파일 길이보다 적용 주체와 함께 변경해야 하는 경계를 기준으로 나눈다.
- **루트에는 `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`를 둔다.** `versions.tf`에는 terraform·provider·backend만, `main.tf`에는 모듈 호출과 모듈 사이에 넘기는 값만 둔다. 루트에 리소스를 직접 두지 않는다.
- **리소스 주소를 바꿀 때는 루트의 `moved.tf`에 `moved` 블록을 둔다.** 적용이 끝나면 다음 PR에서 지운다.
- **두 루트가 공유해야 하는 이름**은 한쪽에서 다른 쪽을 가리키는 주석을 단다. 예: ECR 저장소와 공통 ECS 역할 이름(`modules/iam`의 locals).

적용 주체와 절차는 [운영 가이드](../docs/operations.md), 적용 상태는 [README](../README.md#적용-상태-확인)를 본다. 권한 정책의 의도는 [`bootstrap/tests/`](bootstrap/tests/iam.test.mjs)의 테스트가 기준이다.
