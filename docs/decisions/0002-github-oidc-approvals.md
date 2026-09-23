# 0002. GitHub OIDC와 1인 환경 승인

- 상태: 채택
- 관련 PR: [#1](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/1), [#2](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/2), [#4](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/4)

## 맥락

GitHub Actions가 AWS를 호출해야 하지만 장기 액세스 키는 두지 않는다. 저장소는 한 사람이 운영하고, AI가 브랜치를 push한다.

## 결정

- AWS 역할의 신뢰 정책은 저장소 소유자와 저장소의 immutable ID가 들어간 OIDC subject(`repo:ban-dal@46153202/aws-ecs-fullstack-app@1382568125`)와 GitHub 환경 이름으로 제한한다. 저장소 이름이 바뀌어도 신뢰가 새지 않는다.
- `*-plan`, `*-apply` 환경은 `ban-dal`의 수동 승인을 요구하고 자기 승인을 허용한다(`prevent_self_review=false`). `*-apply`는 `main` 브랜치만 허용한다.
- 환경 보호 규칙을 저장소 변수보다 먼저 만든다. 변수가 먼저 있으면 승인 없이 plan이 실행될 수 있다. fork PR에는 AWS 자격을 주지 않는다.

## 결과와 제약

승인은 독립 검토가 아니라 사람이 누르는 확인 버튼이다. PR plan 승인은 "리뷰 전 브랜치 코드에 AWS 읽기 자격을 줘도 되는가"를 묻는 보안 관문이고, apply 승인만 배포 결정이다.

## 다시 볼 조건

두 번째 리뷰어가 생기면 `prevent_self_review`를 켠다.
