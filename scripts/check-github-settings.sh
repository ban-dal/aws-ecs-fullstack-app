#!/usr/bin/env bash
# Check that GitHub environments and variables match the AWS role design.
# Read-only: prints each mismatch and exits non-zero; it changes nothing.
#
# The repository has one maintainer, so every environment requires `ban-dal`
# and allows self-approval (prevent_self_review=false). An approval is a manual
# confirmation, not an independent review: a PR plan approval decides whether an
# unreviewed branch may run with AWS read credentials, and only an apply
# approval is a deployment decision. Turn prevent_self_review on once a second
# reviewer joins.
#
# Create environment protection before variables. With variables alone, a PR
# plan would run without approval. Fork PRs never receive AWS credentials.
set -euo pipefail

repo="${GITHUB_REPOSITORY:-ban-dal/aws-ecs-fullstack-app}"
reviewer="ban-dal"
failures=0

expect() {
  local description="$1" actual="$2" expected="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "ok   $description"
  else
    echo "FAIL $description: got '${actual}', want '${expected}'"
    failures=$((failures + 1))
  fi
}

# Prints a variable's value, or nothing when it does not exist.
variable_value() {
  local value
  if value="$(gh api "$1" -q .value 2>/dev/null)"; then echo "$value"; fi
}

repo_variable() {
  variable_value "repos/$repo/actions/variables/$1"
}

for name in TF_STATE_BUCKET AWS_ACCOUNT_ID AWS_REGION; do
  expect "repository variable $name is set" "$([[ -n "$(repo_variable "$name")" ]] && echo set)" set
done
# Plan roles are per environment. A repository-level value would silently stand
# in for a missing environment value.
expect "repository variable AWS_PLAN_ROLE_ARN is absent" "$(repo_variable AWS_PLAN_ROLE_ARN)" ""

account="$(repo_variable AWS_ACCOUNT_ID)"

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
