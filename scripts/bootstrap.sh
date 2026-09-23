#!/usr/bin/env bash
# Plan and apply infra/bootstrap from a local session.
#
# The bootstrap root creates the GitHub OIDC roles themselves, so it cannot be
# applied by a workflow. After the pull request merges, a person runs `plan`,
# compares the summary with the scope written in the pull request, and then
# runs `apply` on the same saved plan. Post the apply summary as a comment on
# that pull request.
#
#   scripts/bootstrap.sh plan    # any branch: saved plan, change summary, policy tests
#   scripts/bootstrap.sh apply   # main only: applies the saved plan from `plan`
#
# Which profile applies which change is listed in docs/operations.md.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
tf=(terraform -chdir="$root/infra/bootstrap")
state_bucket="${TF_STATE_BUCKET:-aws-ecs-fullstack-app}"
work="${TMPDIR:-/tmp}/aws-fullstack-bootstrap"

init() {
  "${tf[@]}" init -reconfigure -input=false -no-color \
    -backend-config="bucket=$state_bucket" \
    -backend-config="key=bootstrap/terraform.tfstate" \
    -backend-config="region=ap-northeast-2" >/dev/null
}

summarize() {
  jq -r '
    [.resource_changes[] | select(.change.actions != ["no-op"])
      | {address, action: (.change.actions | join("/"))}] as $changes
    | "create=\([$changes[] | select(.action == "create")] | length)"
      + " update=\([$changes[] | select(.action == "update")] | length)"
      + " delete=\([$changes[] | select(.action == "delete")] | length)"
      + " replace=\([$changes[] | select(.action | test("/"))] | length)",
      ($changes[] | "  \(.action) \(.address)")
  ' "$1"
}

plan() {
  rm -rf "$work"
  mkdir -m 700 "$work"
  git -C "$root" rev-parse HEAD > "$work/commit"
  # A plan of uncommitted code is fine for review but must not be applied.
  [[ -z "$(git -C "$root" status --porcelain -- infra/bootstrap)" ]] || touch "$work/dirty"
  echo "caller: $(aws sts get-caller-identity --query Arn --output text)"
  echo "commit: $(cat "$work/commit")"
  init
  "${tf[@]}" plan -input=false -no-color -var-file=terraform.tfvars -out="$work/bootstrap.tfplan" > "$work/plan.log" 2>&1 \
    || { tail -n 30 "$work/plan.log" >&2; exit 1; }
  "${tf[@]}" show -json "$work/bootstrap.tfplan" > "$work/plan.json"
  summarize "$work/plan.json"
  PLAN_JSON="$work/plan.json" node --test --test-reporter=dot "$root"/infra/bootstrap/policy-tests/*.test.mjs
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

  echo "caller: $(aws sts get-caller-identity --query Arn --output text)"
  echo "commit: $head"
  summarize "$work/plan.json"
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
