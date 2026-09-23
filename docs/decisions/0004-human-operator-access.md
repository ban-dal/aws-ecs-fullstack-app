# 0004. 사람의 운영 접근은 IAM 사용자와 MFA 역할

- 상태: 채택
- 관련 PR: [#6](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/6), [#7](https://github.com/ban-dal/aws-ecs-fullstack-app/pull/7)

## 맥락

초기 bootstrap은 계정 root로 적용했다. 사람의 로컬 운영을 root에서 옮겨야 한다. 독립 계정용 IAM Identity Center account instance는 AWS 계정 접근용 permission set을 지원하지 않는다.

## 결정

- IAM 사용자 `aws-fullstack-lab-operator`는 로그인과 자기 MFA 관리, 역할 수임 권한만 갖는다. 실제 작업은 MFA 세션만 신뢰하는 역할 `aws-fullstack-lab-bootstrap-operator`로 한다. 비밀번호·MFA·액세스 키는 Terraform 밖에서 사용자가 직접 만든다.
- 콘솔 로그인에는 패스키를 쓸 수 있지만 AWS CLI/API는 패스키 MFA를 지원하지 않는다. 역할 수임에는 인증 앱(TOTP) 장치를 쓰고, 장치 이름은 사용자 이름과 같아야 한다.
- Terraform은 `mfa_serial` 프로필에서 MFA 코드를 입력받지 못한다. AWS CLI로 역할을 먼저 수임하고, 캐시된 세션을 `credential_process`로 넘기는 프로필로 Terraform을 실행한다.
- 운영 역할은 자기 역할·사용자·Budget과 GitHub 역할 boundary를 바꾸지 못한다. 이런 bootstrap 변경은 root 세션으로 적용한다.

## 결과와 제약

root는 계정 복구와 위 예외 적용에만 쓴다. 역할 세션은 최대 1시간이다.

## 다시 볼 조건

AWS Organizations를 쓰게 되면([0001](0001-single-account-environments.md)) IAM Identity Center로 옮긴다.
