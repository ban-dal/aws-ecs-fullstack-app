#!/usr/bin/env bash
# GitHub 환경과 변수가 AWS 역할 설계와 맞는지 확인한다.
# 읽기 전용이다. 어긋난 항목을 출력하고 0이 아닌 코드로 끝나며, 아무것도 바꾸지 않는다.
#
# GitHub OIDC 역할은 앱 저장소 배포에만 있다. 인프라 저장소 CI는 AWS 자격 없이 정적 검사만
# 하므로 AWS 값을 담은 secret·변수와 배포 환경을 두지 않는다. 인프라 적용은 scripts/infra.sh다.
set -euo pipefail

repo="${GITHUB_REPOSITORY:-ban-dal/aws-ecs-fullstack-app}"
app_repo="${APP_GITHUB_REPOSITORY:-ban-dal/aws-ecs-fullstack-web}"
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

expect "infra repository has no secrets" "$(gh api "repos/$repo/actions/secrets" -q .total_count)" 0
expect "infra repository has no variables" "$(gh api "repos/$repo/actions/variables" -q .total_count)" 0
expect "infra repository has no environments" "$(gh api "repos/$repo/environments" -q .total_count)" 0

# 앱 저장소는 preprod 브랜치 토큰과 main 전용 prod-deploy 환경으로 배포한다. 계정 ID는
# 공개 로그에서 가려지도록 secret으로 두고, 같은 이름의 변수는 값이 드러나므로 없어야 한다.
expect "app repository secret AWS_ACCOUNT_ID exists" "$(exists "repos/$app_repo/actions/secrets/AWS_ACCOUNT_ID")" yes
expect "app repository variable AWS_ACCOUNT_ID is absent" "$(variable_value "repos/$app_repo/actions/variables/AWS_ACCOUNT_ID")" ""
expect "app repository variable AWS_REGION is absent" "$(variable_value "repos/$app_repo/actions/variables/AWS_REGION")" ""
app_rules="$(gh api "repos/$app_repo/environments/prod-deploy" -q '.protection_rules[] | select(.type == "required_reviewers")')"
expect "app prod-deploy has no required reviewers" "$(jq -r '[.reviewers[].reviewer.login] | join(",")' <<<"$app_rules")" ""
app_branches="$(gh api "repos/$app_repo/environments/prod-deploy/deployment-branch-policies" -q '[.branch_policies[].name] | join(",")')"
expect "app prod-deploy deploys from main only" "$app_branches" main
expect "app preprod branch exists" "$(exists "repos/$app_repo/branches/preprod")" yes

exit $((failures > 0))
