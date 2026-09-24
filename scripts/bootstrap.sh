#!/usr/bin/env bash
# 로컬 세션에서 infra/bootstrap을 plan하고 apply한다.
#
# bootstrap 루트는 GitHub OIDC 역할 자체를 만들기 때문에 workflow로 적용할 수 없다.
# PR이 merge되면 사람이 `plan`을 실행해 요약을 PR에 적힌 범위와 비교하고, 같은 저장
# plan으로 `apply`를 실행한다. apply 요약은 그 PR에 댓글로 남긴다.
#
#   scripts/bootstrap.sh plan    # 모든 브랜치: 저장 plan, 변경 요약, 정책 테스트
#   scripts/bootstrap.sh apply   # main 전용: `plan`이 만든 저장 plan을 적용
#
# 어떤 변경을 어떤 프로필로 적용하는지는 docs/operations.md에 있다.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
tf=(terraform -chdir="$root/infra/bootstrap")
work="${TMPDIR:-/tmp}/aws-fullstack-bootstrap"

# 계정 ID와 state 버킷 이름은 저장소에 두지 않는다. 버킷 이름은 Git에서 제외된
# terraform.tfvars에서 읽고, 출력은 PR 댓글에 붙여 넣을 수 있도록 계정 ID를 가린다.
state_bucket="${TF_STATE_BUCKET:-$(awk -F'"' '/^state_bucket_name[[:space:]]*=/ {print $2}' "$root/infra/bootstrap/terraform.tfvars" 2>/dev/null)}"
[[ -n "$state_bucket" ]] || { echo "state_bucket_name is missing in infra/bootstrap/terraform.tfvars" >&2; exit 1; }

caller() {
  aws sts get-caller-identity --query Arn --output text | sed -E 's/[0-9]{12}/<account-id>/'
}

init() {
  "${tf[@]}" init -reconfigure -input=false -no-color \
    -backend-config="bucket=$state_bucket" \
    -backend-config="key=bootstrap/terraform.tfstate" \
    -backend-config="region=ap-northeast-2" >/dev/null
}

plan() {
  rm -rf "$work"
  mkdir -m 700 "$work"
  git -C "$root" rev-parse HEAD > "$work/commit"
  # 커밋하지 않은 코드의 plan은 검토용으로는 괜찮지만 적용해서는 안 된다.
  [[ -z "$(git -C "$root" status --porcelain -- infra/bootstrap)" ]] || touch "$work/dirty"
  echo "caller: $(caller)"
  echo "commit: $(cat "$work/commit")"
  init
  "${tf[@]}" plan -input=false -no-color -var-file=terraform.tfvars -out="$work/bootstrap.tfplan" > "$work/plan.log" 2>&1 \
    || { tail -n 30 "$work/plan.log" >&2; exit 1; }
  "${tf[@]}" show -json "$work/bootstrap.tfplan" > "$work/plan.json"
  "$root/scripts/tfplan.sh" summary "$work/plan.json"
  PLAN_JSON="$work/plan.json" node --test --test-reporter=dot "$root"/infra/bootstrap/tests/*.test.mjs
  echo "saved plan: $work/bootstrap.tfplan (full output: $work/plan.log)"
}

apply() {
  [[ -f "$work/bootstrap.tfplan" ]] || { echo "no saved plan; run: scripts/bootstrap.sh plan" >&2; exit 1; }
  [[ "$(git -C "$root" branch --show-current)" == main ]] || { echo "apply runs on main only" >&2; exit 1; }
  git -C "$root" fetch -q origin main
  local head
  head="$(git -C "$root" rev-parse HEAD)"
  [[ "$head" == "$(git -C "$root" rev-parse origin/main)" ]] || { echo "main is not at origin/main" >&2; exit 1; }
  [[ "$head" == "$(cat "$work/commit")" ]] || { echo "saved plan was made from another commit; run plan again" >&2; exit 1; }
  [[ ! -f "$work/dirty" ]] || { echo "saved plan includes uncommitted changes; run plan again" >&2; exit 1; }

  echo "caller: $(caller)"
  echo "commit: $head"
  "$root/scripts/tfplan.sh" summary "$work/plan.json"
  init
  "${tf[@]}" apply -input=false -no-color "$work/bootstrap.tfplan" | grep -E '^Apply complete'
  local status=0
  "${tf[@]}" plan -input=false -no-color -detailed-exitcode -var-file=terraform.tfvars >/dev/null || status=$?
  rm -rf "$work"
  echo "post-apply plan exit code: $status (0 = no changes)"
  return "$status"
}

case "${1:-}" in
  plan) plan ;;
  apply) apply ;;
  *) echo "usage: scripts/bootstrap.sh plan|apply" >&2; exit 2 ;;
esac
