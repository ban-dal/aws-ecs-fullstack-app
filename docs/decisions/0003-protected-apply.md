# 0003. 서비스 기반은 main의 보호된 workflow로만 적용

- 상태: 채택
- 관련 PR: [#4](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/4), [#5](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/5)

## 맥락

AI가 작성한 인프라 변경은 사람의 PR 리뷰를 거쳐야 한다. PR CI에서 apply하면 merge 전 코드가 쓰기 권한을 갖는다.

## 결정

- 서비스 리소스(`infra/plan` 루트)는 merge된 `main`에서 `Apply service foundation`을 수동 실행해 적용한다. merge만으로 배포가 시작되지 않는다.
- plan과 apply는 서로 다른 OIDC 역할과 GitHub 환경을 쓴다.
- apply 작업은 저장 plan의 JSON을 검사해 `module.service_foundation` 안의 신규 생성만 허용한다. plan 파일은 민감 정보가 들어갈 수 있어 artifact로 올리지 않는다.
- bootstrap 루트는 이 workflow가 관리하지 않는다. 역할 자신을 만드는 단계라 OIDC로 적용할 수 없으므로, PR merge 후 사람이 저장 plan을 확인하고 로컬에서 적용한다([0004](0004-human-operator-access.md)).

## 결과와 제약

신규 생성만 허용하므로 기존 리소스 수정·교체·삭제는 이 workflow로 적용할 수 없다. apply 승인 뒤에 plan을 다시 만들기 때문에 승인 시점에 본 plan과 적용되는 plan이 같다는 보장이 없다.

## 다시 볼 조건

기존 리소스를 처음 수정해야 할 때. 적용 workflow 개선 작업에서 삭제·교체 차단 중심의 검사와 plan 일치 확인으로 바꿀 예정이다.
