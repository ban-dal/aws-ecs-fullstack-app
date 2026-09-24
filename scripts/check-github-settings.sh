#!/usr/bin/env bash
# GitHub 환경과 변수가 AWS 역할 설계와 맞는지 확인한다.
# 읽기 전용이다. 어긋난 항목을 출력하고 0이 아닌 코드로 끝나며, 아무것도 바꾸지 않는다.
#
# 저장소 관리자가 한 명이므로 모든 환경은 `ban-dal`의 승인을 요구하고 자기 승인을
# 허용한다(prevent_self_review=false). 승인은 독립 검토가 아니라 사람이 누르는 확인
# 버튼이다. PR plan 승인은 리뷰 전 브랜치 코드에 AWS 읽기 자격을 줘도 되는지를
# 정하고, apply 승인만 배포 결정이다. 두 번째 리뷰어가 생기면 prevent_self_review를
# 켠다.
#
# 환경 보호 규칙을 변수보다 먼저 만든다. 변수만 있으면 PR plan이 승인 없이 실행된다.
# fork PR은 AWS 자격을 받지 않는다.
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
for name in AWS_ACCOUNT_ID TF_STATE_BUCKET; do
  expect "repository secret $name exists" "$(exists "repos/$repo/actions/secrets/$name")" yes
  expect "repository variable $name is absent" "$(repo_variable "$name")" ""
done
expect "repository variable AWS_REGION is set" "$([[ -n "$(repo_variable AWS_REGION)" ]] && echo set)" set
# plan 역할은 환경별이다. 저장소 수준 값이 있으면 환경 값이 빠졌을 때 조용히
# 그 자리를 대신한다.
expect "repository variable AWS_PLAN_ROLE_ARN is absent" "$(repo_variable AWS_PLAN_ROLE_ARN)" ""

# secret 값은 읽을 수 없으므로, 역할 ARN의 계정은 로컬 bootstrap 변수와 비교한다.
root="$(git rev-parse --show-toplevel)"
account="$(awk -F'"' '/^expected_account_id[[:space:]]*=/ {print $2}' "$root/infra/bootstrap/terraform.tfvars" 2>/dev/null || true)"
[[ -n "$account" ]] || { echo "expected_account_id is missing in infra/bootstrap/terraform.tfvars" >&2; exit 1; }

for environment in preprod prod; do
  for kind in plan apply; do
    name="$environment-$kind"
    rules="$(gh api "repos/$repo/environments/$name" -q '.protection_rules[] | select(.type == "required_reviewers")')"
    expect "$name requires $reviewer" "$(jq -r '[.reviewers[].reviewer.login] | join(",")' <<<"$rules")" "$reviewer"
    expect "$name allows self-approval" "$(jq -r '.prevent_self_review' <<<"$rules")" false

    if [[ "$kind" == apply ]]; then
      branches="$(gh api "repos/$repo/environments/$name/deployment-branch-policies" -q '[.branch_policies[].name] | join(",")')"
      expect "$name deploys from main only" "$branches" main
      variable=AWS_APPLY_ROLE_ARN
    else
      variable=AWS_PLAN_ROLE_ARN
    fi
    value="$(variable_value "repos/$repo/environments/$name/variables/$variable")"
    expect "$name $variable" "$value" "arn:aws:iam::$account:role/aws-fullstack-lab-$name"
  done
done

exit $((failures > 0))
