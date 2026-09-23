# 0005. GitHub 역할 permissions boundary와 환경 태그 격리

- 상태: 채택
- 관련 PR: [#8](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/8)

## 맥락

운영 역할은 GitHub 역할의 정책과 신뢰 정책을 관리한다. 제한이 없으면 GitHub 역할을 자신이 수임하도록 고쳐 계정 관리자 수준 권한을 얻을 수 있었다. 또한 preprod 적용 역할이 prod 네트워크를 바꿀 수 있었고, 공유 plan 역할이 두 환경 state를 모두 읽었다.

## 결정

- 모든 GitHub 역할에 관리형 정책 `aws-fullstack-lab-github-boundary`를 boundary로 붙인다. boundary는 서비스 단위 상한(환경 state 경로, 서울 리전 `ec2:*`·`ecr:*`)만 두고 IAM·STS는 넣지 않는다. 액션 단위 제한은 역할 정책이 맡는다.
- 운영 역할은 boundary를 읽기만 한다. boundary 제거·교체와 boundary 없는 역할 재생성은 Deny로 막는다.
- plan 역할은 환경별로 나누고 자기 state만 읽는다. 적용 역할의 EC2 생성은 요청 태그 `Environment`, 부모 VPC와 기존 리소스 변경은 리소스 태그 `Environment`로 제한한다.
- boundary ARN은 이름으로 만든 local 값을 쓴다. 새 리소스 ARN을 참조하면 의존하는 정책 JSON이 plan에서 가려진다.
- bootstrap에는 provider `default_tags`를 쓰지 않는다. 모든 리소스의 태그가 바뀌면 IAM 정책 data source가 apply 시점으로 미뤄져, 저장 plan에서 정책 내용을 검토할 수 없다.

## 결과와 제약

새 AWS 서비스(ECS, ALB 등)를 쓰려면 같은 PR에서 boundary를 넓히고 root로 적용해야 한다. 이 확장을 사람이 검토하는 지점으로 삼는다. 태그 조건은 IAM 시뮬레이터로 검증했지만, 쓰기 경로는 실제 변경에서 처음 쓰인다.

## 다시 볼 조건

ECS용 IAM 역할처럼 GitHub 역할이 `iam:PassRole`을 써야 할 때. 역할은 bootstrap에서 만들고 boundary에는 그 ARN에 대한 `iam:PassRole`만 더하는 방향을 먼저 검토한다.
