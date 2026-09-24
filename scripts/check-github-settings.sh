#!/usr/bin/env bash
# GitHub 환경과 변수가 AWS 역할 설계와 맞는지 확인한다.
# 읽기 전용이다. 어긋난 항목을 출력하고 0이 아닌 코드로 끝나며, 아무것도 바꾸지 않는다.
#
# 사람의 승인은 배포 결정인 `*-apply`에만 둔다. 저장소 관리자가 한 명이므로 `ban-dal`의
# 승인을 요구하고 자기 승인을 허용한다(prevent_self_review=false). `*-apply`는 `main`
# 브랜치에서만 배포한다.
#
# `*-plan`에는 승인 규칙을 두지 않는다. 같은 저장소 브랜치를 push할 수 있는 사람이
# 관리자뿐이라, PR plan 승인은 관리자가 자기 코드에 읽기 자격을 주는 확인일 뿐이다.
# fork PR은 AWS 자격을 받지 않는다. 쓰기 권한자를 추가하면 plan 역할이 state를
# 읽을 수 있으므로 `*-plan`의 필수 승인자와 prevent_self_review를 다시 켠다.
set -euo pipefail

repo="${GITHUB_REPOSITORY:-ban-dal/aws-ecs-fullstack-app}"
reviewer="ban-dal"
failures=0

# 출력은 PR 댓글에 붙여 넣을 수 있도록 계정 ID를 가린다.
mask() {
  sed -E 's/[0-9]{12}/<account-id>/g' <<<"$1"
}

expect() {
  local description="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   $description"
  else
    echo "FAIL $description: got '$(mask "$actual")', want '$(mask "$expected")'"
    failures=$((failures + 1))
  fi
}

exists() {
  if gh api "$1" --silent 2>/dev/null; then echo yes; else echo no; fi
}

# 변수 값을 출력한다. 변수가 없으면 아무것도 출력하지 않는다.
variable_value() {
  local value
  if value="$(gh api "$1" -q .value 2>/dev/null)"; then echo "$value"; fi
}

repo_variable() {
  variable_value "repos/$repo/actions/variables/$1"
}

# 계정 ID와 state 버킷 이름은 공개 로그에서 가려지도록 secret으로 둔다. 같은 이름의
# 변수가 남아 있으면 값이 로그에 드러나므로 없어야 한다.
for name in AWS_ACCOUNT_ID TF_STATE_BUCKET CLIENT_VPN_SERVER_CERTIFICATE_ARN; do
  expect "repository secret $name exists" "$(exists "repos/$repo/actions/secrets/$name")" yes
  expect "repository variable $name is absent" "$(repo_variable "$name")" ""
done
expect "repository variable AWS_REGION is set" "$([[ -n "$(repo_variable AWS_REGION)" ]] && echo set)" set
for variable in AWS_PLAN_ROLE_ARN AWS_APPLY_ROLE_ARN; do
  expect "unused repository variable $variable is absent" "$(repo_variable "$variable")" ""
done
for environment in preprod prod; do
  for kind in plan apply; do
    name="$environment-$kind"
    rules="$(gh api "repos/$repo/environments/$name" -q '.protection_rules[] | select(.type == "required_reviewers")')"
    reviewers="$(jq -r '[.reviewers[].reviewer.login] | join(",")' <<<"$rules")"
    if [[ "$kind" == plan ]]; then
      expect "$name has no required reviewers" "$reviewers" ""
    else
      expect "$name requires $reviewer" "$reviewers" "$reviewer"
      expect "$name allows self-approval" "$(jq -r '.prevent_self_review' <<<"$rules")" false
      branches="$(gh api "repos/$repo/environments/$name/deployment-branch-policies" -q '[.branch_policies[].name] | join(",")')"
      expect "$name deploys from main only" "$branches" main
    fi
    for variable in AWS_PLAN_ROLE_ARN AWS_APPLY_ROLE_ARN; do
      expect "unused $name variable $variable is absent" "$(variable_value "repos/$repo/environments/$name/variables/$variable")" ""
    done
  done
done

exit $((failures > 0))
